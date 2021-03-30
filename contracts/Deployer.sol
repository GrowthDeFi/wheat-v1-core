// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Buyback } from "./Buyback.sol";
import { CustomMasterChef } from "./CustomMasterChef.sol";
import { FeeCollector } from "./FeeCollector.sol";
import { RewardCompoundingStrategyToken } from "./RewardCompoundingStrategyToken.sol";
import { WHEAT, stkWHEAT } from "./Tokens.sol";

import { Factory } from "./interop/UniswapV2.sol";

import { $ } from "./network/$.sol";

contract Deployer is Ownable
{
	address constant DEFAULT_ADMIN = 0xBf70B751BB1FC725bFbC4e68C4Ec4825708766c5; // S
	address constant DEFAULT_TREASURY = 0x2165fa4a32B9c228cD55713f77d2e977297D03e8; // G
	address constant DEFAULT_DEV = 0x7674D2a14076e8af53AC4ba9bBCf0c19FeBe8899;

	uint256 constant INITIAL_WHEAT_PER_BLOCK = 1e18;

	address public exchange;
	address public admin;
	address public treasury;
	address public dev;
	address public collector;
	address public buyback;
	address public wheat;
	address public stkWheat;
	address public masterChef;
	address[] public strategies;

	bool public deployed = false;

	constructor () public
	{
		require($.NETWORK == $.network(), "wrong network");
	}

	function deploy() external onlyOwner
	{
		require(!deployed, "deploy unavailable");

		admin = DEFAULT_ADMIN;
		treasury = DEFAULT_TREASURY;
		dev = DEFAULT_DEV;

		// configure MasterChef
		wheat = LibDeployer1.publish_WHEAT();
		stkWheat = LibDeployer1.publish_stkWHEAT(wheat);
		masterChef = LibDeployer2.publish_CustomMasterChef(wheat, stkWheat, INITIAL_WHEAT_PER_BLOCK, block.number);

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

		// publish strategy tokens
		addStrategy("staked BNB/CAKE", "stkBNB/CAKE", 1, $.CAKE, 20000);
		addStrategy("staked BNB/BUSD", "stkBNB/BUSD", 2, $.WBNB, 5000);
		addStrategy("staked BNB/BTCB", "stkBNB/BTCB", 15, $.WBNB, 3000);
		addStrategy("staked BNB/ETH", "stkBNB/ETH", 14, $.WBNB, 3000);
		addStrategy("staked BETH/ETH", "stkBETH/ETH", 70, $.ETH, 2000);
		addStrategy("staked BNB/LINK", "stkBNB/LINK", 7, $.WBNB, 1000);
		addStrategy("staked BNB/UNI", "stkBNB/UNI", 25, $.WBNB, 1000);
		addStrategy("staked BNB/DOT", "stkBNB/DOT", 5, $.WBNB, 1000);
		addStrategy("staked BNB/ADA", "stkBNB/ADA", 3, $.WBNB, 1000);
		addStrategy("staked BUSD/UST", "stkBUSD/UST", 63, $.BUSD, 1000);
		addStrategy("staked BUSD/DAI", "stkBUSD/DAI", 52, $.BUSD, 1000);
		addStrategy("staked BUSD/USDC", "stkBUSD/USDC", 53, $.BUSD, 1000);
		addStrategy("staked BTCB/bBADGER", "stkBTCB/bBADGER", 106, $.BTCB, 1000);
		addStrategy("staked BNB/BSCX", "stkBNB/BSCX", 51, $.WBNB, 1000);
		addStrategy("staked BNB/BRY", "stkBNB/BRY", 75, $.WBNB, 1000);
		addStrategy("staked BNB/WATCH", "stkBNB/WATCH", 84, $.WBNB, 1000);
		addStrategy("staked BNB/BTCST", "stkBNB/BTCST", 55, $.WBNB, 1000);
		addStrategy("staked BNB/bOPEN", "stkBNB/bOPEN", 0, $.WBNB, 1000); // TODO find out pid for pair
		addStrategy("staked BUSD/IOTX", "stkBUSD/IOTX", 81, $.BUSD, 1000);
		addStrategy("staked BUSD/TPT", "stkBUSD/TPT", 85, $.BUSD, 1000);
		addStrategy("staked BNB/ZIL", "stkBNB/ZIL", 108, $.WBNB, 1000);
		addStrategy("staked BNB/TWT", "stkBNB/TWT", 12, $.WBNB, 1000);

		buyback = LibDeployer1.publish_Buyback($.CAKE, $.WBNB, wheat, $.GRO);
		collector = LibDeployer1.publish_FeeCollector($.PancakeSwap_MASTERCHEF, buyback);

		uint256[] memory _hodllist = new uint256[](22);
		_hodllist[0] = 1;
		_hodllist[1] = 2;
		_hodllist[2] = 3;
		_hodllist[3] = 5;
		_hodllist[4] = 7;
		_hodllist[5] = 12;
		_hodllist[6] = 14;
		_hodllist[7] = 15;
		_hodllist[8] = 25;
		_hodllist[9] = 51;
		_hodllist[10] = 52;
		_hodllist[11] = 53;
		_hodllist[12] = 55;
		_hodllist[13] = 63;
		_hodllist[14] = 70;
		_hodllist[15] = 75;
		_hodllist[16] = 81;
		_hodllist[17] = 84;
		_hodllist[18] = 85;
		_hodllist[19] = 0; // TODO find out pid for pair
		_hodllist[20] = 106;
		_hodllist[21] = 108;
		FeeCollector(collector).updateHodllist(_hodllist, true);

		// transfer ownerships
		Ownable(wheat).transferOwnership(masterChef);
		Ownable(stkWheat).transferOwnership(masterChef);
		Ownable(masterChef).transferOwnership(admin);
		Ownable(collector).transferOwnership(admin);
		for (uint256 _i = 0; _i < strategies.length; _i++) {
			Ownable(strategies[_i]).transferOwnership(admin);
		}

		// wrap up the deployment
		renounceOwnership();
		deployed = true;
		emit DeployPerformed();
	}

	function addStrategy(string memory _name, string memory _symbol, uint256 _pid, address _routingToken, uint256 _allocPoint) internal
	{
		address _address = LibDeployer3.publish_RewardCompoundingStrategyToken(_name, _symbol, 18, $.PancakeSwap_MASTERCHEF, _pid, _routingToken, dev, treasury, collector);
		RewardCompoundingStrategyToken(_address).setExchange(exchange);
		CustomMasterChef(masterChef).add(_allocPoint, IERC20(_address), false);
		strategies.push(_address);
	}

	event DeployPerformed();
}

library LibDeployer1
{
	function publish_WHEAT() public returns (address _address)
	{
		return address(new WHEAT());
	}

	function publish_stkWHEAT(address _wheat) public returns (address _address)
	{
		return address(new stkWHEAT(_wheat));
	}

	function publish_Buyback(address _rewardToken, address _routingToken, address _buybackToken1, address _buybackToken2) public returns (address _address)
	{
		return address(new Buyback(_rewardToken, _routingToken, _buybackToken1, _buybackToken2));
	}

	function publish_FeeCollector(address _masterChef, address _buyback) public returns (address _address)
	{
		return address(new FeeCollector(_masterChef, _buyback));
	}
}

library LibDeployer2
{
	function publish_CustomMasterChef(address _wheat, address _stkWheat, uint256 _cakePerBlock, uint256 _startBlock) public returns (address _address)
	{
		return address(new CustomMasterChef(_wheat, _stkWheat, _cakePerBlock, _startBlock));
	}
}

library LibDeployer3
{
	function publish_RewardCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector) public returns (address _address)
	{
		return address(new RewardCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef, _pid, _routingToken, _dev, _treasury, _collector));
	}
}
