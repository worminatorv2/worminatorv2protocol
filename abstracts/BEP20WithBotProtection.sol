// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libs/SafeMath.sol";
import "./BEP20WithTransferLock.sol";
import "../interfaces/IHoneyBotV0Token.sol";

abstract contract BEP20WithBotProtection is BEP20WithTransferLock, IHoneyBotV0Token {
    using SafeMath for uint256;

    // --==[ FEES ]==--
    // Fees numbers are multiplied by 100
    uint256 public botBuyFee = 2500; // 25% - to lure bots
    uint256 public botSellFee = 3500; // 35% - almost max slippage

    uint256 public botTokenHoldersPart = 5000; // 50%
    uint256 public botLpPart = 1500; // 15%
    uint256 public botBurnPart = 500; // 5%
    uint256 public botProjectPart = 3000; // 30%

    // --==[ WALLETS ]==--
    address public botLaunchpad;
    mapping(address => bool) public botWhitelist;
    mapping(address => bool) public botBlacklist;

    // --==[ PROTECTION ]==--
    bool public botProtectionIsActive = false;
    uint256 public botProtectionEndBlock = 0;
    address[] public bots;

    // --==[ Events ]==--
    event BotDetected(address indexed bot);

    modifier onlyLaunchpad() {
        require(botLaunchpad == _msgSender(), "BEP20WithBotProtection: only launchpad can call this function");
        _;
    }

    constructor(string memory name, string memory symbol) BEP20WithTransferLock(name, symbol) internal {
        botWhitelist[_msgSender()] = true;
    }

    function prepareForInitialLiquidity() external override onlyLaunchpad {
        isTransferLocked = false;
    }

    function warmupBotProtection(uint256 firewallBlockLength) external override onlyLaunchpad {
        require(!botProtectionIsActive, "BEP20WithBotProtection: bot protection is active");
        require(firewallBlockLength <= 50, "BEP20WithBotProtection: bot firewall is too long");
        _startBotProtection(firewallBlockLength);
    }

    function setBotFees(uint256 buyFee, uint256 sellFee) external onlyOwner {
        require(buyFee <= 10000, "BEP20WithBotProtection: buy fee is too high");
        require(sellFee <= 10000, "BEP20WithBotProtection: sell fee is too high");
        botBuyFee = buyFee;
        botSellFee = sellFee;
    }

    function setBotLaunchpad(address launchpad) external onlyOwner {
        require(botLaunchpad != launchpad, "BEP20WithBotProtection: launchpad is the same");
        botLaunchpad = launchpad;
    }

    function setBotWhitelist(address account, bool isWhitelisted) external onlyOwner {
        botWhitelist[account] = isWhitelisted;
        if (isWhitelisted) {
            botBlacklist[account] = false;
        }
    }

    function setBotBlacklist(address account, bool isBlacklisted) external onlyOwner {
        if (isBlacklisted) {
            _addToBotList(account);
        } else {
            botBlacklist[account] = false;
        }
    }

    function startBotProtection(uint256 firewallBlockLength) external onlyOwner {
        _startBotProtection(firewallBlockLength);
    }

    function haltBotProtection() external onlyOwner {
        botProtectionIsActive = false;
        botProtectionEndBlock = 0;
    }

    function _startBotProtection(uint256 firewallBlockLength) private {
        botProtectionIsActive = true;
        botProtectionEndBlock = block.number.add(firewallBlockLength);
    }

    // --==[ Overridden methods ]==--
    function _transfer(address from, address to, uint256 amount) override botProtected(from, to) internal {
        super._transfer(from, to, amount);
    }

    modifier botProtected(address from, address to) {
        bool isBotTransfer = isPotentialBot(from) || isPotentialBot(to);

        if (isBotTransfer) {
            require(isPair(from) || isPair(to), "BEP20WithBotProtection: Bots are only allowed to trade.");
            setBotFees();
        }

        _;
        if (isBotTransfer) restoreBotFees();
    }

    function isPotentialBot(address account) internal returns (bool) {
        if (!botProtectionIsActive) return false;
        if (isPair(account)) return false;
        if (botWhitelist[account]) return false;

        if (botProtectionEndBlock >= block.number) {
            _addToBotList(account);
        }

        return botBlacklist[account];
    }

    function _addToBotList(address bot) private {
        if (!botBlacklist[bot]) {
            botBlacklist[bot] = true;
            bots.push(bot);
        }

        emit BotDetected(bot);
    }

    uint256 private prevBuyFee;
    uint256 private prevSellFee;

    uint256 private prevTokenHoldersPart;
    uint256 private prevLpPart;
    uint256 private prevBurnPart;
    uint256 private prevProjectPart;

    function setBotFees() private {
        prevBuyFee = buyFee;
        prevSellFee = sellFee;
        prevTokenHoldersPart = tokenHoldersPart;
        prevLpPart = lpPart;
        prevBurnPart = burnPart;
        prevProjectPart = projectPart;

        buyFee = botBuyFee;
        sellFee = botSellFee;
        tokenHoldersPart = botTokenHoldersPart;
        lpPart = botLpPart;
        burnPart = botBurnPart;
        projectPart = botProjectPart;
    }

    function restoreBotFees() private {
        buyFee = prevBuyFee;
        sellFee = prevSellFee;
        tokenHoldersPart = prevTokenHoldersPart;
        lpPart = prevLpPart;
        burnPart = prevBurnPart;
        projectPart = prevProjectPart;
    }
}
