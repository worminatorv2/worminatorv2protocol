// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "./SafeMath.sol";

library SwapUtilities {
    using SafeMath for uint256;

    function swapTokensForETH(
        address routerAddress,
        address tokenAddress,
        address receiver,
        uint256 tokenAmount,
        uint256 timeout
    ) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        // generate the pancake pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = router.WETH();

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            receiver,
            block.timestamp + timeout
        );
    }

    function addLiquidity(
        address routerAddress,
        address tokenAddress,
        address receiver,
        uint256 tokenAmount,
        uint256 ethAmount
    ) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            tokenAddress,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            receiver,
            block.timestamp
        );
    }
}