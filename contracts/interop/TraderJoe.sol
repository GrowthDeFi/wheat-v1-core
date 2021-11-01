// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface JoeBar is IERC20
{
	function joe() external view returns (address _joe);

	function enter(uint256 _amount) external;
	function leave(uint256 _shares) external;
}

interface MasterChefJoe
{
	function pendingTokens(uint256 _pid, address _user) external view returns (uint256 _pendingJoe, address _bonusTokenAddress, string memory _bonusTokenSymbol, uint256 _pendingBonusToken);
	function poolLength() external view returns (uint256 _poolLength);
	function userInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt);

	function deposit(uint256 _pid, uint256 _amount) external;
	function withdraw(uint256 _pid, uint256 _amount) external;
	function emergencyWithdraw(uint256 _pid) external;
}

interface MasterChefJoeV2 is MasterChefJoe
{
	function joe() external view returns (address _joe);
	function poolInfo(uint256 _pid) external view returns (address _lpToken, uint256 _allocPoint, uint256 _lastRewardTimestamp, uint256 _accJoePerShare, address _rewarder);
}

interface MasterChefJoeV3 is MasterChefJoe
{
	function JOE() external view returns (address _JOE);
	function poolInfo(uint256 _pid) external view returns (address _lpToken, uint256 _accJoePerShare, uint256 _lastRewardTimestamp, uint256 _allocPoint, address _rewarder);
}
