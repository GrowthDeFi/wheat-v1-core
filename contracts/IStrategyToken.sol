// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategyToken is IERC20
{
	function reserveToken() external view returns (address _reserveToken);
	function totalReserve() external view returns (uint256 _totalReserve);
	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares);
	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount);

	function deposit(uint256 _amount) external;
	function withdraw(uint256 _shares) external;
}
