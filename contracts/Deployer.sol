// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Buyback } from "./Buyback.sol";
import { CustomMasterChef } from "./CustomMasterChef.sol";
import { FeeCollector } from "./FeeCollector.sol";
import { RewardCompoundingStrategyToken } from "./RewardCompoundingStrategyToken.sol";
import { WHEAT, stkWHEAT } from "./Tokens.sol";

import { Factory, Pair } from "./interop/UniswapV2.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { $ } from "./network/$.sol";

contract Deployer is Ownable
{
	address constant DEFAULT_ADMIN = 0xBf70B751BB1FC725bFbC4e68C4Ec4825708766c5; // S
	address constant DEFAULT_TREASURY = 0x2165fa4a32B9c228cD55713f77d2e977297D03e8; // G
	address constant DEFAULT_DEV = 0x7674D2a14076e8af53AC4ba9bBCf0c19FeBe8899;
	address constant DEFAULT_YIELD = 0xBf70B751BB1FC725bFbC4e68C4Ec4825708766c5; // S

	uint256 public constant INITIAL_WHEAT_PER_BLOCK = 1e18;

	uint256 public constant WHEAT_LIQUIDITY_ALLOCATION = 10000e18; // 10k WHEAT
	uint256 public constant WBNB_LIQUIDITY_ALLOCATION = 275e18; // ~100k USD at deploy

	address public admin;
	address public treasury;
	address public dev;
	address public yield;

	address public exchange;

	address public wheat;
	address public stkWheat;
	address public masterChef;
	address public buyback;

	enum Stage {
		Deploy, Batch1, Batch2, Batch3, Batch4, Batch5, Batch6, Done
	}

	Stage public stage = Stage.Deploy;

	constructor () public
	{
		require($.NETWORK == $.network(), "wrong network");
	}

	function deploy() external payable onlyOwner
	{
		require(stage == Stage.Deploy, "unavailable");

		uint256 _amount = msg.value;
		require(_amount == WBNB_LIQUIDITY_ALLOCATION, "BNB amount mismatch");

		// wraps LP liquidity BNB into WBNB
		Wrapping._wrap($.WBNB, WBNB_LIQUIDITY_ALLOCATION);

		admin = DEFAULT_ADMIN;
		treasury = DEFAULT_TREASURY;
		dev = DEFAULT_DEV;

		exchange = $.WHEAT_EXCHANGE_IMPL;

		// configure MasterChef
		wheat = LibDeployer1.publish_WHEAT();
		stkWheat = LibDeployer2.publish_stkWHEAT(wheat);
		masterChef = LibDeployer3.publish_CustomMasterChef(wheat, stkWheat, INITIAL_WHEAT_PER_BLOCK, block.number);

		CustomMasterChef(masterChef).set(0, 15000, false);

		address _factory = $.UniswapV2_Compatible_FACTORY;
		address _BNB_WHEAT = Factory(_factory).createPair($.WBNB, wheat);
		address _BNB_GRO = Factory(_factory).getPair($.WBNB, $.GRO);
		address _GRO_gROOT = Factory(_factory).getPair($.GRO, $.gROOT);
		address _BNB_gROOT = Factory(_factory).getPair($.WBNB, $.gROOT);
		CustomMasterChef(masterChef).add(30000, IERC20(_BNB_WHEAT), false);
		CustomMasterChef(masterChef).add(3000, IERC20(_BNB_GRO), false);
		CustomMasterChef(masterChef).add(1000, IERC20(_GRO_gROOT), false);
		CustomMasterChef(masterChef).add(1000, IERC20(_BNB_gROOT), false);

		// adds the liquidity to the WHEAT/BNB LP
		WHEAT(wheat).mint(_BNB_WHEAT, WHEAT_LIQUIDITY_ALLOCATION);
		Transfers._pushFunds($.WBNB, _BNB_WHEAT, WBNB_LIQUIDITY_ALLOCATION);
		Pair(_BNB_WHEAT).mint(DEFAULT_TREASURY);

		buyback = LibDeployer2.publish_Buyback($.CAKE, $.WBNB, wheat, $.GRO, treasury, yield);
		Buyback(buyback).setExchange(exchange);

		require(Transfers._getBalance($.WBNB) == 0, "WBNB left over");
		require(Transfers._getBalance(wheat) == 0, "WHEAT left over");
		require(Transfers._getBalance(_BNB_WHEAT) == 0, "BNB/WHEAT LP shares left over");

		// transfer ownerships
		Ownable(wheat).transferOwnership(masterChef);
		Ownable(stkWheat).transferOwnership(masterChef);
		Ownable(buyback).transferOwnership(admin);

		stage = Stage.Batch1;
	}

	function batch1() external onlyOwner
	{
		require(stage == Stage.Batch1, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BNB/CAKE", "stkBNB/CAKE", 1, $.CAKE, 20000);
			addStrategy("staked BNB/BUSD", "stkBNB/BUSD", 2, $.WBNB, 5000);
			addStrategy("staked BNB/BTCB", "stkBNB/BTCB", 15, $.WBNB, 3000);
			addStrategy("staked BNB/ETH", "stkBNB/ETH", 14, $.WBNB, 3000);
		}
		if ($.NETWORK == $.Network.Bsctest) {
			addStrategy("staked BNB/CAKE", "stkBNB/CAKE", 2, $.CAKE, 20000);
			addStrategy("staked BNB/ETH", "stkBNB/ETH", 1, $.WBNB, 3000);
		}
		stage = Stage.Batch2;
	}

	function batch2() external onlyOwner
	{
		require(stage == Stage.Batch2, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BETH/ETH", "stkBETH/ETH", 70, $.ETH, 2000);
			addStrategy("staked BNB/LINK", "stkBNB/LINK", 7, $.WBNB, 1000);
			addStrategy("staked BNB/UNI", "stkBNB/UNI", 25, $.WBNB, 1000);
			addStrategy("staked BNB/DOT", "stkBNB/DOT", 5, $.WBNB, 1000);
		}
		stage = Stage.Batch3;
	}

	function batch3() external onlyOwner
	{
		require(stage == Stage.Batch3, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BNB/ADA", "stkBNB/ADA", 3, $.WBNB, 1000);
			addStrategy("staked BUSD/UST", "stkBUSD/UST", 63, $.BUSD, 1000);
			addStrategy("staked BUSD/DAI", "stkBUSD/DAI", 52, $.BUSD, 1000);
			addStrategy("staked BUSD/USDC", "stkBUSD/USDC", 53, $.BUSD, 1000);
		}
		stage = Stage.Batch4;
	}

	function batch4() external onlyOwner
	{
		require(stage == Stage.Batch4, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BTCB/bBADGER", "stkBTCB/bBADGER", 106, $.BTCB, 1000);
			addStrategy("staked BNB/BSCX", "stkBNB/BSCX", 51, $.WBNB, 1000);
			addStrategy("staked BNB/BRY", "stkBNB/BRY", 75, $.WBNB, 1000);
			addStrategy("staked BNB/WATCH", "stkBNB/WATCH", 84, $.WBNB, 1000);
		}
		stage = Stage.Batch5;
	}

	function batch5() external onlyOwner
	{
		require(stage == Stage.Batch5, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BNB/BTCST", "stkBNB/BTCST", 55, $.WBNB, 1000);
			addStrategy("staked BNB/bOPEN", "stkBNB/bOPEN", 79, $.WBNB, 1000);
			addStrategy("staked BUSD/IOTX", "stkBUSD/IOTX", 81, $.BUSD, 1000);
			addStrategy("staked BUSD/TPT", "stkBUSD/TPT", 85, $.BUSD, 1000);
		}
		stage = Stage.Batch6;
	}

	function batch6() external onlyOwner
	{
		require(stage == Stage.Batch6, "unavailable");
		if ($.NETWORK == $.Network.Bscmain) {
			addStrategy("staked BNB/ZIL", "stkBNB/ZIL", 108, $.WBNB, 1000);
			addStrategy("staked BNB/TWT", "stkBNB/TWT", 12, $.WBNB, 1000);
		}

		// transfer ownerships
		Ownable(masterChef).transferOwnership(admin);
		renounceOwnership();

		stage = Stage.Done;
		emit DeployPerformed();
	}

	function addStrategy(string memory _name, string memory _symbol, uint256 _pid, address _routingToken, uint256 _allocPoint) internal
	{
		address _collector = LibDeployer1.publish_FeeCollector($.PancakeSwap_MASTERCHEF, _pid, buyback, treasury);
		address _strategy = LibDeployer4.publish_RewardCompoundingStrategyToken(_name, _symbol, 18, $.PancakeSwap_MASTERCHEF, _pid, _routingToken, dev, treasury, _collector);
		RewardCompoundingStrategyToken(_strategy).setExchange(exchange);
		Ownable(_collector).transferOwnership(admin);
		Ownable(_strategy).transferOwnership(admin);
		CustomMasterChef(masterChef).add(_allocPoint, IERC20(_strategy), false);
	}

	event DeployPerformed();
}

library LibDeployer1
{
	function publish_WHEAT() public returns (address _address)
	{
		return address(new WHEAT());
	}

	function publish_FeeCollector(address _masterChef, uint256 _pid, address _buyback, address _treasury) public returns (address _address)
	{
		return address(new FeeCollector(_masterChef, _pid, _buyback, _treasury));
	}
}

library LibDeployer2
{
	function publish_stkWHEAT(address _wheat) public returns (address _address)
	{
		return address(new stkWHEAT(_wheat));
	}

	function publish_Buyback(address _rewardToken, address _routingToken, address _buybackToken1, address _buybackToken2, address _treasury, address _yield) public returns (address _address)
	{
		return address(new Buyback(_rewardToken, _routingToken, _buybackToken1, _buybackToken2, _treasury, _yield));
	}
}

library LibDeployer3
{
	function publish_CustomMasterChef(address _wheat, address _stkWheat, uint256 _cakePerBlock, uint256 _startBlock) public returns (address _address)
	{
		return address(new CustomMasterChef(_wheat, _stkWheat, _cakePerBlock, _startBlock));
	}
}

library LibDeployer4
{
	function publish_RewardCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector) public returns (address _address)
	{
		return address(new RewardCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef, _pid, _routingToken, _dev, _treasury, _collector));
	}
}
