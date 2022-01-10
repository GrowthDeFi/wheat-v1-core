// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

import { IERC20Historical } from "./IERC20Historical.sol";

contract StakingToken is IERC20Historical, ERC20, ReentrancyGuard
{
	using SafeMath for uint256;

	struct UserInfo {
		uint256 amount;
	}

	struct Point {
		uint256 bias;
		uint256 time;
	}

	address public immutable reserveToken;

	mapping(address => UserInfo) public userInfo;

	Point[] private points_;
	mapping(address => Point[]) private userPoints_;

	constructor(string memory _name, string memory _symbol, uint8 _decimals, address _reserveToken)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		reserveToken = _reserveToken;
	}

	function deposit(uint256 _amount) external nonReentrant
	{
		UserInfo storage _user = userInfo[msg.sender];
		uint256 _oldAmount = _user.amount;
		uint256 _newAmount = _oldAmount.add(_amount);
		_user.amount = _newAmount;
		Transfers._pullFunds(reserveToken, msg.sender, _amount);
		_mint(msg.sender, _amount);
		_checkpoint(msg.sender, _newAmount, totalSupply());
		emit Deposit(msg.sender, _amount);
	}

	function withdraw(uint256 _amount) external nonReentrant
	{
		UserInfo storage _user = userInfo[msg.sender];
		uint256 _oldAmount = _user.amount;
		require(_amount <= _oldAmount, "insufficient balance");
		uint256 _newAmount = _oldAmount - _amount;
		_user.amount = _newAmount;
		_burn(msg.sender, _amount);
		Transfers._pushFunds(reserveToken, msg.sender, _amount);
		_checkpoint(msg.sender, _newAmount, totalSupply());
		emit Withdraw(msg.sender, _amount);
	}

	function checkpoint() external override
	{
	}

	function totalSupply(uint256 _when) public override view returns (uint256 _totalSupply)
	{
		Point[] storage _points = points_;
		uint256 _index = _findPoint(_points, _when);
		if (_index == 0) return 0;
		Point storage _point = _points[_index - 1];
		return _point.bias;
	}

	function balanceOf(address _account, uint256 _when) public override view returns (uint256 _balance)
	{
		Point[] storage _points = userPoints_[_account];
		uint256 _index = _findPoint(_points, _when);
		if (_index == 0) return 0;
		Point storage _point = _points[_index - 1];
		return _point.bias;
	}

	function _findPoint(Point[] storage _points, uint256 _when) internal view returns (uint256 _index)
	{
		uint256 _min = 0;
		uint256 _max = _points.length;
		if (_when >= block.timestamp) return _max;
		while (_min < _max) {
			uint256 _mid = (_min + _max) / 2;
			if (_points[_mid].time <= _when)
				_min = _mid + 1;
			else
				_max = _mid;
		}
		return _min;
	}

	function _appendPoint(Point[] storage _points, uint256 _bias, uint256 _time) internal
	{
		uint256 _length = _points.length;
		if (_length > 0) {
			Point storage _point = _points[_length - 1];
			if (_point.bias == _bias) return;
			if (_point.time == _time) {
				_point.bias = _bias;
				return;
			}
			require(_time > _point.time, "invalid time");
		}
		_points.push(Point({ bias: _bias, time: _time }));
	}

	function _checkpoint(address _account, uint256 _balance, uint256 _totalSupply) internal
	{
		_appendPoint(points_, _totalSupply, block.timestamp);
		_appendPoint(userPoints_[_account], _balance, block.timestamp);
	}

	event Deposit(address indexed _account, uint256 _amount);
	event Withdraw(address indexed _account, uint256 _amount);
}
