// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libs/SafeMath.sol";
import "../libs/SwapUtilities.sol";
import "./BEP20WithFee.sol";

contract FarmVault {
    constructor() public {
    }
}

abstract contract BEP20WithFarmRouter is BEP20WithFee {
    using SafeMath for uint256;

    // --==[ Strategies ]==--
    uint256 private constant FARM_STRATEGY_SELL_DIRECTLY = 1;
    uint256 private constant FARM_STRATEGY_SELL_VIA_CONTRACT = 2;
    uint256 private farm_strategy;

    // --==[ FEES ]==--
    // Fees numbers are multiplied by 100
    uint256 public farmRewardDistribution = 5000; // 50%

    // --==[ WALLETS ]==--
    address public farmSink;
    address public farmVault;

    // --==[ Events ]==--
    event FarmRewarded(uint256 amount, uint256 strategy);

    bool public isFarmSinkActive = true;
    bool public isFarmRewardingActive = true;
    uint256 public farmNumberOfTokensToSell = 8888e18;

    constructor(string memory name, string memory symbol) BEP20WithFee(name, symbol) internal {
        farm_strategy = FARM_STRATEGY_SELL_DIRECTLY;
        farmSink = _msgSender();
        farmVault = address(new FarmVault());
    }

    function setFarmRewardDistribution(uint256 distribution) onlyOwner external {
        require(distribution <= 10000, "BEP20WithFarmRouter: distribution should be less than 100%");
        farmRewardDistribution = distribution;
    }

    function setFarmSink(address destination) onlyOwner external {
        require(destination != address(0), "BEP20WithFarmRouter: farm sink can't be zero address");
        farmSink = destination;
    }

    function setFarmStrategy(uint256 strategy) onlyOwner external {
        farm_strategy = strategy;
    }

    function setFarmSinkActive(bool isActive) onlyOwner external {
        isFarmSinkActive = isActive;
    }

    function setFarmRewardingActive(bool isActive) onlyOwner external {
        isFarmRewardingActive = isActive;
    }

    function setFarmNumberOfTokensToSell(uint256 numberOfTokens) onlyOwner external {
        farmNumberOfTokensToSell = numberOfTokens;
    }

    // --==[ Overridden methods ]==--
    function _transfer(address from, address to, uint256 amount) override internal virtual {
        bool overMinTokenBalance = BEP20.balanceOf(farmVault) >= farmNumberOfTokensToSell;
        bool internalSwap = (from == address(this) && isPair(to)); // don't trigger infinite loop

        if (
            isFarmRewardingActive &&
            !internalSwap &&
            !isPair(from) &&
            overMinTokenBalance &&
            !isLocked()
        ) {
            forwardRewardsToSink(farmNumberOfTokensToSell);
        }
        super._transfer(from, to, amount);
    }

    function addRewards(address from, uint256 amount) override internal {
        uint256 rewardAmount = amount;

        if (isFarmSinkActive) {
            uint256 farmAmount = amount.mul(farmRewardDistribution).div(10000);
            BEP20._transfer(from, farmVault, farmAmount);
            rewardAmount = amount.sub(farmAmount);
        }

        // transfer rewards from payer to contract address
        super.addRewards(from, rewardAmount);
    }

    // for testing purposes
    function triggerForwardRewardsToSink(uint256 amount) external onlyOwner {
        require(BEP20.balanceOf(farmVault) >= amount, "BEP20WithFarmRouter: insufficient vault balance");
        forwardRewardsToSink(amount);
    }

    function forwardRewardsToSink(uint256 amount) private lock {
        if (amount == 0 || farmSink == address(0) || swapRouter == address(0)) return;

        if (farm_strategy == FARM_STRATEGY_SELL_DIRECTLY) {
            farmRouterTransfer1(amount);
        } else if (farm_strategy == FARM_STRATEGY_SELL_VIA_CONTRACT) {
            farmRouterTransfer2(amount);
        }
    }

    function farmRouterTransfer1(uint256 amount) private {
        BEP20._transfer(farmVault, address(this), amount);
        _approve(address(this), swapRouter, amount);

        SwapUtilities.swapTokensForETH(swapRouter, address(this), farmSink, amount, swapRouterSellTimeout);

        emit FarmRewarded(amount, FARM_STRATEGY_SELL_DIRECTLY);
    }

    function farmRouterTransfer2(uint256 amount) private {
        BEP20._transfer(farmVault, address(this), amount);
        _approve(address(this), swapRouter, amount);

        uint256 balanceBeforeSwap = address(this).balance;
        SwapUtilities.swapTokensForETH(swapRouter, address(this), address(this), amount, swapRouterSellTimeout);
        uint256 rewardAmount = address(this).balance.sub(balanceBeforeSwap);

        payable(farmSink).transfer(rewardAmount);

        emit FarmRewarded(amount, FARM_STRATEGY_SELL_VIA_CONTRACT);
    }
}
