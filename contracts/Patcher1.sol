// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Buyback } from "./Buyback.sol";
import { NativeBridge } from "./NativeBridge.sol";
import { stkBNB } from "./Tokens.sol";

import { $ } from "./network/$.sol";

contract Patcher1 is Ownable
{
	address constant DEFAULT_ADMIN = 0xAD4E38B274720c1a6c7fB8B735C5FAD112DF9A13;
	address constant DEFAULT_TREASURY = 0x0d1d68C73b57a53B1DdCD287aCf4e66Ed745B759;
	address constant DEFAULT_DEV = 0x7674D2a14076e8af53AC4ba9bBCf0c19FeBe8899;
	address constant DEFAULT_YIELD = 0x0d1d68C73b57a53B1DdCD287aCf4e66Ed745B759;

	address public admin;
	address public treasury;
	address public dev;
	address public yield;

	address public exchange;

	address public stkBnb;
	address public buyback;
	address public bridge;

	enum Stage {
		Deploy, Done
	}

	Stage public stage = Stage.Deploy;

	constructor () public
	{
		require($.NETWORK == $.network(), "wrong network");
	}

	function deploy() external onlyOwner
	{
		require(stage == Stage.Deploy, "unavailable");

		admin = DEFAULT_ADMIN;
		treasury = DEFAULT_TREASURY;
		dev = DEFAULT_DEV;
		yield = DEFAULT_YIELD;

		exchange = $.WHEAT_EXCHANGE_IMPL;

		bridge = LibPatcher1_2.new_NativeBridge($.WBNB);

		buyback = LibPatcher1_2.new_Buyback($.WBNB, $.WBNB, $.WHEAT, $.GRO, treasury, yield);
		Buyback(buyback).setExchange(exchange);

		stkBnb = LibPatcher1_1.new_stkBNB(dev, treasury, buyback);
		stkBNB(stkBnb).addToWhitelist(bridge);

		// this step needs to be done manually
		// MasterChefAdmin(masterChefAdmin).add(_allocPoint, IERC20(stkBnb), false);

		// transfer ownerships
		Ownable(stkBnb).transferOwnership(admin);
		Ownable(buyback).transferOwnership(admin);
		renounceOwnership();

		stage = Stage.Done;
		emit DeployPerformed();
	}

	event DeployPerformed();
}

library LibPatcher1_1
{
	function new_stkBNB(address _dev, address _treasury, address _buyback) public returns (address _address)
	{
		return address(new stkBNB(_dev, _treasury, _buyback));
	}
}

library LibPatcher1_2
{
	function new_NativeBridge(address _nativeToken) public returns (address _address)
	{
		return address(new NativeBridge(_nativeToken));
	}

	function new_Buyback(address _rewardToken, address _routingToken, address _buybackToken1, address _buybackToken2, address _treasury, address _yield) public returns (address _address)
	{
		return address(new Buyback(_rewardToken, _routingToken, _buybackToken1, _buybackToken2, _treasury, _yield));
	}
}
