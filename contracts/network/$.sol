// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev This library is provided for convenience. It is the single source for
 *      the current network and all related hardcoded contract addresses.
 */
library $
{
	enum Network {
		Bscmain, Bsctest
	}

	Network constant NETWORK = Network.Bscmain;

	function chainId() internal pure returns (uint256 _chainid)
	{
		assembly { _chainid := chainid() }
		return _chainid;
	}

	function network() internal pure returns (Network _network)
	{
		uint256 _chainid = chainId();
		if (_chainid == 56) return Network.Bscmain;
		if (_chainid == 97) return Network.Bsctest;
		require(false, "unsupported network");
	}

	address constant UniswapV2_Compatible_FACTORY =
		NETWORK == Network.Bscmain ? 0xBCfCcbde45cE874adCB698cC183deBcF17952812 :
		NETWORK == Network.Bsctest ? 0x81B26284AF48472775Ca472F44DC3a67aE0eaA1f :
		0x0000000000000000000000000000000000000000;

	address constant UniswapV2_Compatible_ROUTER02 =
		NETWORK == Network.Bscmain ? 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F :
		NETWORK == Network.Bsctest ? 0x59870703523f8E67dE3c018FdA61C00732f2318E :
		0x0000000000000000000000000000000000000000;

	address constant PancakeSwap_MASTERCHEF =
		NETWORK == Network.Bscmain ? 0x73feaa1eE314F8c655E354234017bE2193C9E24E :
		NETWORK == Network.Bsctest ? 0x7C83Cab4B208A0cD5a1b222D8e6f9099C8F37897 :
		0x0000000000000000000000000000000000000000;

	address constant WBNB =
		NETWORK == Network.Bscmain ? 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c :
		NETWORK == Network.Bsctest ? 0xd21BB48C35e7021Bf387a8b259662dC06a9df984 :
		0x0000000000000000000000000000000000000000;

	address constant GRO =
		NETWORK == Network.Bscmain ? 0x336eD56D8615271b38EcEE6F4786B55d0EE91b96 :
		NETWORK == Network.Bsctest ? 0x01c0E10BFd2721D5770e9600b6db2091Da28810d :
		0x0000000000000000000000000000000000000000;

	address constant gROOT =
		NETWORK == Network.Bscmain ? 0x8B571fE684133aCA1E926bEB86cb545E549C832D :
		NETWORK == Network.Bsctest ? 0x46c29d2793691C8063719258fa45b656F164FEb1 :
		0x0000000000000000000000000000000000000000;

	address constant CAKE =
		NETWORK == Network.Bscmain ? 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 :
		NETWORK == Network.Bsctest ? 0x2a94738549370A3973Ba778BbC5A424C83C8c633 :
		0x0000000000000000000000000000000000000000;

	address constant ETH =
		NETWORK == Network.Bscmain ? 0x2170Ed0880ac9A755fd29B2688956BD959F933F8 :
		NETWORK == Network.Bsctest ? 0xd66c6B4F0be8CE5b39D52E0Fd1344c389929B378 :
		0x0000000000000000000000000000000000000000;

	address constant BTCB =
		NETWORK == Network.Bscmain ? 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c :
		NETWORK == Network.Bsctest ? 0x6ce8dA28E2f864420840cF74474eFf5fD80E65B8 :
		0x0000000000000000000000000000000000000000;

	address constant BUSD =
		NETWORK == Network.Bscmain ? 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 :
		NETWORK == Network.Bsctest ? 0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee :
		0x0000000000000000000000000000000000000000;
}
