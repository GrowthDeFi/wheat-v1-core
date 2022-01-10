// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Historical is IERC20
{
	function totalSupply(uint256 _when) external view returns (uint256 _totalSupply);
	function balanceOf(address _account, uint256 _when) external view returns (uint256 _balance);
}
