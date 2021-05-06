// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

interface BeltStrategyToken
{
	function amountToShares(uint256 _amount) external view returns (uint256 _shares);
	function token() external view returns (address _token);

	function deposit(uint256 _amount, uint256 _minShares) external;
}
