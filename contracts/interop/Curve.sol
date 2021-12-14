// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

interface CurveSwap
{
	function get_virtual_price() external view returns (uint256 _virtualPrice);
	function lp_token() external view returns (address _lpToken);
	function underlying_coins(uint256 _i) external view returns (address _coin);

	function add_liquidity(uint256[3] calldata _amounts, uint256 _minTokenAmount, bool _useInderlying) external returns (uint256 _tokenAmount);
	function remove_liquidity_one_coin(uint256 _tokenAmount, int128 _i, uint256 _minAmount, bool _useUnderlying) external returns (uint256 _amount);
}

interface CurveGauge
{
	function lp_token() external view returns (address _lpToken);

	function claim_rewards(address _account, address _receiver) external;
	function deposit(uint256 _amount, address _account, bool _claimRewards) external;
	function withdraw(uint256 _amount, bool _claimRewards) external;
}
