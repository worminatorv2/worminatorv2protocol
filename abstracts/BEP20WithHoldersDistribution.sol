// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libs/BEP20.sol";
import "../libs/SafeMath.sol";

contract RewardsVault {
    constructor() public {
    }
}

abstract contract BEP20WithHoldersDistribution is BEP20 {
    using SafeMath for uint256;

    address public rewardsVault;

    mapping(address => bool) public rewardsExcluded;
    mapping(address => uint256) public lastTotalDividends;

    constructor(string memory name, string memory symbol) BEP20(name, symbol) internal {
        rewardsVault = address(new RewardsVault());
        rewardsExcluded[_msgSender()] = true;
        rewardsExcluded[rewardsVault] = true;
    }

    function _calcRewards(address account) internal view virtual returns (uint256) {
        if (rewardsExcluded[account]) return 0;

        uint256 _balance = super.balanceOf(account);
        uint256 _dividends = super.balanceOf(rewardsVault);
        uint256 _lastTotalDividends = lastTotalDividends[account];

        // just to be safe.
        if (_dividends <= _lastTotalDividends) return 0;

        // difference between current dividends and last dividends represents hold time
        // then we multiply it by holder's % from total supply
        return _dividends.sub(_lastTotalDividends).mul(_balance).div(totalSupply());
    }

    modifier _distribute(address account) {
        uint256 rewards = _calcRewards(account);
        BEP20._transfer(rewardsVault, account, rewards);
        lastTotalDividends[account] = super.balanceOf(rewardsVault);
        _;
    }

    function excludeFromRewards(address account) _distribute(account) public onlyOwner {
        rewardsExcluded[account] = true;
    }

    function includeInRewards(address account) _distribute(account) public onlyOwner {
        delete rewardsExcluded[account];
    }

    function addRewards(address from, uint256 amount) internal virtual {
        BEP20._transfer(from, rewardsVault, amount);
    }

    /**
     * @dev See {BEP20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return super.balanceOf(account) + _calcRewards(account);
    }
}
