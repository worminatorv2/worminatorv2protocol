// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libs/SafeMath.sol";
import "./BEP20WithFarmRouter.sol";

abstract contract BEP20WithTransferLock is BEP20WithFarmRouter {
    using SafeMath for uint256;

    bool public isTransferLocked = false;

    // --==[ WALLETS ]==--
    mapping(address => bool) public transferWhitelist;

    constructor(string memory name, string memory symbol) BEP20WithFarmRouter(name, symbol) internal {
        transferWhitelist[_msgSender()] = true;
    }

    function setTransferLocked(bool isLocked) external onlyOwner {
        isTransferLocked = isLocked;
    }

    function setTransferWhitelist(address account, bool isWhitelisted) external onlyOwner {
        transferWhitelist[account] = isWhitelisted;
    }

    // --==[ Overridden methods ]==--
    function _transfer(address from, address to, uint256 amount) override internal virtual {
        require(
            !isTransferLocked || transferWhitelist[from] || transferWhitelist[to],
            "BEP20WithTransferLock: transfer is locked"
        );
        super._transfer(from, to, amount);
    }
}
