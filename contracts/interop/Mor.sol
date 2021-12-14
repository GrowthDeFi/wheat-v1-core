// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

interface PSM
{
	function dai() external view returns (address _dai);
	function gemJoin() external view returns (address _gemJoin);
	function tout() external view returns (uint256 _tout);

	function sellGem(address _account, uint256 _amount) external;
	function buyGem(address _account, uint256 _amount) external;
}
