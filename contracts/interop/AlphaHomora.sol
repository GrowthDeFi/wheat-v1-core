// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Bank is IERC20
{
	function totalBNB() external view returns (uint256 _totalBNB);

	function deposit() external payable;
	function withdraw(uint256 _shares) external;
}
