// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libs/SafeMath.sol";
import "../libs/SwapUtilities.sol";
import "./PairsHolder.sol";
import "./BEP20WithHoldersDistribution.sol";

abstract contract BEP20WithFee is BEP20WithHoldersDistribution, PairsHolder {
    using SafeMath for uint256;

    // --==[ Router ]==--
    address public swapRouter;
    uint256 public swapRouterSellTimeout = 0;

    // --==[ Strategies ]==--
    uint256 private constant LIQUIDITY_STRATEGY_SEND_TOKENS = 1;
    uint256 private constant LIQUIDITY_STRATEGY_SELL_LIQUIFY = 2;
    uint256 private liquidity_strategy;
    uint256 public liquidityVaultMinBalance = 8888e18;

    // --==[ FEES ]==--
    // Fees numbers are multiplied by 100
    uint256 public buyFee = 500; // 5%
    uint256 public sellFee = 1000; // 10%

    uint256 public tokenHoldersPart = 5000; // 50%
    uint256 public lpPart = 2500; // 25%
    uint256 public burnPart = 1000; // 10%
    uint256 public projectPart = 1500; // 15%

    // --==[ WALLETS ]==--
    address public teamWallet;
    mapping(address => bool) public taxless;

    bool public isFeeActive = true;
    bool public isRewardActive = true;
    uint256 public minPairBalanceToStartLiquify = 444444e18;

    // --==[ TOTALS ]==--
    uint256 public totalBurnFee;
    uint256 public totalLpFee;
    uint256 public totalProtocolFee;
    uint256 public totalHoldersFee;

    // --==[ Events ]==--
    event LpRewarded(address indexed lpPair, uint256 amount);
    event FeesUpdated(
        uint256 indexed buyFee,
        uint256 indexed sellFee,
        uint256 tokenHoldersPart,
        uint256 lpPart,
        uint256 burnPart,
        uint256 projectPart
    );

    bool private locked;
    modifier lock {
        require(!locked, "Locked");
        locked = true;
        _;
        locked = false;
    }

    function isLocked() internal view returns (bool) {
        return locked;
    }

    constructor(string memory name, string memory symbol) BEP20WithHoldersDistribution(name, symbol) internal {
        liquidity_strategy = LIQUIDITY_STRATEGY_SELL_LIQUIFY;
        teamWallet = _msgSender();
    }

    // --==[ External methods ]==--
    function setLiquidityStrategy(uint256 strategy) onlyOwner external {
        require(liquidity_strategy != strategy, "BEP20WithFee: liquidity strategy is the same");
        liquidity_strategy = strategy;
    }

    function setSwapRouter(address router) onlyOwner external {
        require(router != address(0), "BEP20WithFee: farm router can't be zero address");
        swapRouter = router;
    }

    function setSwapRouterSellTimeout(uint256 timeout) onlyOwner external {
        swapRouterSellTimeout = timeout;
    }

    function setLiquidityVaultMinBalance(uint256 amount) onlyOwner external {
        liquidityVaultMinBalance = amount;
    }

    function setFees(
        uint256 buyFee_,
        uint256 sellFee_,
        uint256 tokenHoldersPart_,
        uint256 lpPart_,
        uint256 burnPart_,
        uint256 projectPart_
    ) external onlyOwner {
        require(buyFee_ < 10000, "BEP20WithFee: Buy fee should be less than 100%");
        require(sellFee_ < 10000, "BEP20WithFee: Sell fee should be less than 100%");
        require(
            tokenHoldersPart_.add(lpPart_).add(burnPart_).add(projectPart_) == 10000,
            "BEP20WithFee: Sum of tokenHolders/lp/burn/project parts should be 10000 (100%)"
        );

        buyFee = buyFee_;
        sellFee = sellFee_;
        tokenHoldersPart = tokenHoldersPart_;
        lpPart = lpPart_;
        burnPart = burnPart_;
        projectPart = projectPart_;

        emit FeesUpdated(buyFee, sellFee, tokenHoldersPart, lpPart, burnPart, projectPart);
    }

    function setMinPairBalanceToStartLiquify(uint256 amount) external onlyOwner {
        minPairBalanceToStartLiquify = amount;
    }

    function setFeeActive(bool value) external onlyOwner {
        isFeeActive = value;
    }

    function setRewardActive(bool value) external onlyOwner {
        isRewardActive = value;
    }

    function setTaxless(address account, bool value) public onlyOwner {
        require(account != address(0), "Taxless is zero-address");
        taxless[account] = value;
    }

    function setTeamWallet(address account) external onlyOwner {
        require(account != address(0), "BEP20WithFee: Team wallet is zero-address");
        require(teamWallet != account, "BEP20WithFee: Team wallet is the same");

        // include old project wallet to rewards
        if (teamWallet != address(0)) {
            setTaxless(teamWallet, false);
            includeInRewards(teamWallet);
        }

        teamWallet = account;

        // exclude new team wallet from rewards
        setTaxless(teamWallet, true);
        excludeFromRewards(teamWallet);
    }

    function withdrawFees(address receiver, uint256 amount) external onlyOwner {
        require(receiver != address(0), "BEP20WithFee: receiver is zero-address");
        require(address(this).balance > amount, "BEP20WithFee: balance is less than amount");
        payable(receiver).transfer(amount);
    }

    // --==[ Overridden methods ]==--
    function _transfer(address from, address to, uint256 amount) override _distribute(from) internal virtual {
        checkAndLiquify(from, to);

        bool isTrading = isPair(from) || isPair(to);

        if (!isTrading || !isFeeActive || taxless[from] || taxless[to] || taxless[msg.sender]) {
            super._transfer(from, to, amount);
            return;
        }

        bool isBuying = from == msg.sender && isPair(from);
        (uint256 feePart, address lpPair, address feePayer) = isBuying ? (buyFee, from, to) : (sellFee, to, from);

        uint256 totalFees = amount.mul(feePart).div(10000);
        (uint256 holdersFee, uint256 lpFee, uint256 burnFee, uint256 projectFee) = calcFees(totalFees);

        {
            // increasing total values
            totalHoldersFee = totalHoldersFee.add(holdersFee);
            totalBurnFee = totalBurnFee.add(burnFee);
            totalLpFee = totalLpFee.add(lpFee);
            totalProtocolFee = totalProtocolFee.add(projectFee);
        }

        _processPayment(from, to, amount, holdersFee, lpFee, burnFee, projectFee, lpPair, feePayer);
    }

    function _processPayment(
        address from, address to, uint256 amount,
        uint256 holdersFee, uint256 lpFee, uint256 burnFee,
        uint256 projectFee, address lpPair, address feePayer
    ) private {
        // in the case of buying we should transfer all amount to buyer and then take fees from it
        if (feePayer == to) {
            super._transfer(from, to, amount);
        }

        if (isRewardActive) {
            // transfer holders fee part
            addRewards(feePayer, holdersFee);
        } else {
            // if rewards are not active — just burn excess
            super._burn(feePayer, holdersFee);
        }

        // transfer LP part
        super._transfer(feePayer, pair_vaults[lpPair], lpFee);
        // burn the burning fee part
        super._burn(feePayer, burnFee);
        // transfer project fee part
        super._transfer(feePayer, teamWallet, projectFee);

        // selling - fee is taken from the seller
        if (feePayer == from) {
            amount = amount.sub(holdersFee).sub(burnFee).sub(lpFee).sub(projectFee);
            super._transfer(from, to, amount);
        }
    }

    // --==[ Private methods ]==--
    function calcFees(uint256 amount)
    private view
    returns (uint256 holdersFee, uint256 lpFee, uint256 burnFee, uint256 projectFee)
    {
        // Calc TokenHolders part
        holdersFee = amount.mul(tokenHoldersPart).div(10000);
        lpFee = amount.mul(lpPart).div(10000);
        burnFee = amount.mul(burnPart).div(10000);
        projectFee = amount.mul(projectPart).div(10000);
    }

    function checkAndLiquify(address from, address to) private {
        if (isLocked()) return;

        uint256 pairs_length = pairsLength();

        // this loop is safe because pairs length would never been more than 25
        for (uint256 idx = 0; idx < pairs_length; idx++) {
            address pair = pairs[idx];
            address vault = getPairVault(pair);

            bool overMinTokenBalance = BEP20.balanceOf(vault) >= liquidityVaultMinBalance;
            bool internalSwap = (from == address(this) && isPair(to)); // don't trigger infinite loop

            if (
                !isLocked() &&
                !internalSwap &&
                overMinTokenBalance &&
                from != pair // couldn't liquify if sender is the same pair!
            ) {
                liquifyPair(vault, pair, liquidityVaultMinBalance);
            }
        }
    }

    function liquifyPair(address vault, address pair, uint256 amount) private lock {
        if (liquidity_strategy == LIQUIDITY_STRATEGY_SEND_TOKENS) {
            // only reward LP when token balance greater then minimum
            if (balanceOf(pair) >= minPairBalanceToStartLiquify) {
                liquifyPair1(vault, pair, amount);
            }
        } else if (liquidity_strategy == LIQUIDITY_STRATEGY_SELL_LIQUIFY) {
            liquifyPair2(vault, amount); // only liquify ETH-token pair
        }

        emit LpRewarded(pair, amount);
    }

    function liquifyPair1(address vault, address pair, uint256 amount) private {
        BEP20._transfer(vault, pair, amount);
        IUniswapV2Pair(pair).sync();
    }

    function liquifyPair2(address vault, uint256 amount) private {
        BEP20._transfer(vault, address(this), amount);
        _approve(address(this), address(swapRouter), amount);

        uint256 half_to_sell = amount.div(2);
        uint256 half_to_liquify = amount.sub(half_to_sell);

        uint256 balance_before_sell = address(this).balance;
        SwapUtilities.swapTokensForETH(swapRouter, address(this), address(this), half_to_sell, swapRouterSellTimeout);
        uint256 balance_to_liquify = address(this).balance.sub(balance_before_sell);
        SwapUtilities.addLiquidity(swapRouter, address(this), teamWallet, half_to_liquify, balance_to_liquify);
    }
}