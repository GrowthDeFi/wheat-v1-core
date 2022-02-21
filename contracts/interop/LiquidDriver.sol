// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

interface MasterChefLqdrV2
{
	function LQDR() external view returns (address _LQDR);
	function lpToken(uint256 _pid) external view returns (address _lpToken);
	function pendingLqdr(uint256 _pid, address _user) external view returns (uint256 _pending);
	function poolInfo(uint256 _pid) external view returns (uint256 _accLqdrPerShare, uint256 _lastRewardBlock, uint256 _allocPoint, uint256 _depositFee);
	function poolLength() external view returns (uint256 _poolLength);
	function userInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt);

	function deposit(uint256 _pid, uint256 _amount, address _to) external;
	function withdraw(uint256 _pid, uint256 _amount, address _to) external;
	function harvest(uint256 _pid, address _to) external;
	function emergencyWithdraw(uint256 _pid, address _to) external;
}
