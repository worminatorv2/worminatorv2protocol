// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IHoneyBotV0Token {
    /**
     * @dev Called before the liquidity is added.
     */
    function prepareForInitialLiquidity() external;

    /**
     * @dev Called immediately after the liquidity is added.
     */
    function warmupBotProtection(uint256 firewallBlockLength) external;
}