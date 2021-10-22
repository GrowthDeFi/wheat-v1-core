// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface JRewardDistributor
{
	function joeAddress() external view returns (address _joe);

	function claimReward(uint8 _rewardType, address payable[] memory _accounts, address[] memory _jtokens, bool _borrowers, bool _suppliers) external payable;
}

interface Joetroller
{
	function rewardDistributor() external view returns (address _rewardDistributor);
}

interface JToken is IERC20
{
	function joetroller() external view returns (address _joetroller);
	function underlying() external view returns (address _token);

	function balanceOfUnderlying(address _account) external returns (uint256 _amount);
	function mint(uint256 _amount) external returns (uint256 _errorCode);
	function redeemUnderlying(uint256 _amount) external returns (uint256 _errorCode);
}
