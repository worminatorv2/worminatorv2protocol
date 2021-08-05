// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/Address.sol";
import "./abstracts/BEP20WithBotProtection.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract Wormoon is BEP20WithBotProtection("Worminator v2 Protocol", "WRMNTOR") {
    using Address for address;

    address public WETHPair;

    constructor(address router) public {
        if (router != address(0)) {
            swapRouter = router;
            WETHPair = _createPair(router, IUniswapV2Router02(router).WETH());
        }

        _addSystemAddress(address(this));
        _addSystemAddress(_msgSender());
        _addSystemAddress(teamWallet);
        _addSystemAddress(farmVault);
        _addSystemAddress(rewardsVault);

        // minting 1b to the owner
        _mint(_msgSender(), 1_000_000_000e18);
    }

    receive() external payable {}

    function _createPair(address router, address token1) private returns (address) {
        address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).createPair(address(this), token1);
        _addPairToTrack(pair);
        rewardsExcluded[pair] = true;
        _addSystemAddress(getPairVault(pair));
        return pair;
    }

    // --==[ Public functions ]==--
    function addPairToTrack(address pair) external onlyOwner {
        _addPairToTrack(pair);
        rewardsExcluded[pair] = true;
        _addSystemAddress(getPairVault(pair));
    }

    function setFarmVault(address vault) external onlyOwner {
        require(vault != address(0), "Farm vault can't be zero address");
        _addSystemAddress(vault);
        farmVault = vault;
    }

    function addSystemAddress(address system_address) external onlyOwner {
        _addSystemAddress(system_address);
    }

    function withdrawGarbageTokens(address receiver, address tokenAddress) external onlyOwner {
        require(tokenAddress != address(0), "Wormoon: token address is zero");
        require(IBEP20(tokenAddress).balanceOf(address(this)) > 0, "Wormoon: garbage token balance is 0");

        uint256 balance = IBEP20(tokenAddress).balanceOf(address(this));
        IBEP20(tokenAddress).transfer(receiver, balance);
    }

    function _addSystemAddress(address system_address) private {
        transferWhitelist[system_address] = true;
        botWhitelist[system_address] = true;
        rewardsExcluded[system_address] = true;
        setTaxless(system_address, true);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external {
        uint256 decreasedAllowance = allowance(account, _msgSender()).sub(
            amount, "BEP20: burn amount exceeds allowance"
        );

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }
}
