const Exchange = artifacts.require('Exchange');
const UniversalBuyback = artifacts.require('UniversalBuyback');
const PancakeSwapFeeCollector = artifacts.require('PancakeSwapFeeCollector');
const PancakeSwapCompoundingStrategyToken = artifacts.require('PancakeSwapCompoundingStrategyToken');
const AutoFarmFeeCollectorAdapter = artifacts.require('AutoFarmFeeCollectorAdapter');
const AutoFarmCompoundingStrategyToken = artifacts.require('AutoFarmCompoundingStrategyToken');
const PantherSwapBuybackAdapter = artifacts.require('PantherSwapBuybackAdapter');
const PantherSwapCompoundingStrategyToken = artifacts.require('PantherSwapCompoundingStrategyToken');

module.exports = async (deployer, network, [account]) => {
  if (network !== 'bscmain') return;

  const OWNER = '0xAD4E38B274720c1a6c7fB8B735C5FAD112DF9A13'; // GrowthDeFi admin multisig
  const TREASURY = '0x0d1d68C73b57a53B1DdCD287aCf4e66Ed745B759'; // GrowthDeFi treasury multisig
  const DEV = '0x7674D2a14076e8af53AC4ba9bBCf0c19FeBe8899'; // GrowthDeFi development fund wallet

  const PANCAKESWAP_ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E'; // PancakeSwap V2 router

  const AUTOFARM_MASTERCHEF = '0x0895196562C7868C5Be92459FaE7f877ED450452'; // AutoFarm MasterChef-like
  const PANCAKESWAP_MASTERCHEF = '0x73feaa1eE314F8c655E354234017bE2193C9E24E'; // PancakeSwap MasterChef
  const PANTHERSWAP_MASTERCHEF = '0x058451C62B96c594aD984370eDA8B6FD7197bbd4'; // PantherSwap MasterChef

  const AUTO = '0xa184088a740c695E156F91f5cC086a06bb78b827'; // Auto Token
  const BUSD = '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56'; // Binance-USD Token
  const CAKE = '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82'; // Cake Token
  const GRO = '0x336eD56D8615271b38EcEE6F4786B55d0EE91b96'; // Growth Token
  const PANTHER = '0x1f546aD641B56b86fD9dCEAc473d1C7a357276B7'; // Panther Token
  const WBNB = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c'; // Wrapped-BNB Token
  const WHEAT = '0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E'; // Wheat Token

  const POOL_4BELT = '0xAEA4f7dcd172997947809CE6F12018a6D5c1E8b6'; // 4Belt Pool

  // deploys Exchange contract
  console.log('Publishing Exchange contract...');
  await deployer.deploy(Exchange, PANCAKESWAP_ROUTER, TREASURY);
  const exchange = await Exchange.deployed();
  await exchange.transferOwnership(OWNER);
  const EXCHANGE = exchange.address;

  // deploys UniversalBuyback contract
  console.log('Publishing UniversalBuyback contract...');
  await deployer.deploy(UniversalBuyback, CAKE, WHEAT, GRO, TREASURY, EXCHANGE);
  const universalBuyback = await UniversalBuyback.deployed();
  await universalBuyback.transferOwnership(OWNER);
  const CAKE_BUYBACK = universalBuyback.address;

  // deploys PancakeSwapFeeCollectorcontract for pool 0 (CAKE staking)
  console.log('Publishing PancakeSwapFeeCollectorcontract contract...');
  await deployer.deploy(PancakeSwapFeeCollector, PANCAKESWAP_MASTERCHEF, 0, CAKE, TREASURY, CAKE_BUYBACK, EXCHANGE);
  const pancakeSwapFeeCollector = await PancakeSwapFeeCollector.deployed();
  await pancakeSwapFeeCollector.transferOwnership(OWNER);
  const CAKE_COLLECTOR = pancakeSwapFeeCollector.address;

  // deploys PancakeSwapCompoundingStrategyToken for pool 0 (CAKE)
  console.log('Publishing PancakeSwapCompoundingStrategyToken contract...');
  await deployer.deploy(PancakeSwapCompoundingStrategyToken, 'staked CAKE', 'stkCAKE', 18, PANCAKESWAP_MASTERCHEF, 0, CAKE, DEV, TREASURY, CAKE_COLLECTOR, EXCHANGE);
  const pancakeSwapCompoundingStrategyToken = await PancakeSwapCompoundingStrategyToken.deployed();
  await pancakeSwapCompoundingStrategyToken.transferOwnership(OWNER);
  const CAKE_STRATEGY = pancakeSwapCompoundingStrategyToken.address;

  // deploys AutoFarmFeeCollectorAdapter AUTO => CAKE
  console.log('Publishing AutoFarmFeeCollectorAdapter contract...');
  await deployer.deploy(AutoFarmFeeCollectorAdapter, AUTO, CAKE, TREASURY, CAKE_COLLECTOR, EXCHANGE);
  const autoFarmFeeCollectorAdapter = await AutoFarmFeeCollectorAdapter.deployed();
  await autoFarmFeeCollectorAdapter.transferOwnership(OWNER);
  const AUTO_COLLECTOR = autoFarmFeeCollectorAdapter.address;

  // deploys AutoFarmCompoundingStrategyToken for pool 341 (4BELT)
  console.log('Publishing AutoFarmCompoundingStrategyToken contract...');
  await deployer.deploy(AutoFarmCompoundingStrategyToken, 'staked 4BELTv2', 'stk4BELT', 18, AUTOFARM_MASTERCHEF, 341, BUSD, true, POOL_4BELT, 3, TREASURY, AUTO_COLLECTOR, EXCHANGE);
  const autoFarmCompoundingStrategyToken = await AutoFarmCompoundingStrategyToken.deployed();
  await autoFarmCompoundingStrategyToken.transferOwnership(OWNER);
  const AUTO_STRATEGY = autoFarmCompoundingStrategyToken.address;

  // deploys PantherSwapBuybackAdapter PANTHER => CAKE
  console.log('Publishing PantherSwapBuybackAdapter contract...');
  await deployer.deploy(PantherSwapBuybackAdapter, PANTHER, CAKE, TREASURY, CAKE_BUYBACK, EXCHANGE);
  const pantherSwapBuybackAdapter = await PantherSwapBuybackAdapter.deployed();
  await pantherSwapBuybackAdapter.transferOwnership(OWNER);
  const PANTHER_BUYBACK = pantherSwapBuybackAdapter.address;

  // deploys PantherSwapCompoundingStrategyToken for pool 0 (CAKE staking)
  console.log('Publishing PantherSwapCompoundingStrategyToken contract...');
  await deployer.deploy(PantherSwapCompoundingStrategyToken, 'staked BNB/BUSDv', 'stkBNB/BUSD', 18, PANTHERSWAP_MASTERCHEF, 18, WBNB, DEV, TREASURY, PANTHER_BUYBACK, EXCHANGE);
  const pantherSwapCompoundingStrategyToken = await PantherSwapCompoundingStrategyToken.deployed();
  await pantherSwapCompoundingStrategyToken.transferOwnership(OWNER);
  const PANTHER_STRATEGY = pantherSwapCompoundingStrategyToken.address;

  // prints summary with addresses
  console.log('EXCHANGE=' + EXCHANGE);
  console.log('CAKE_BUYBACK=' + CAKE_BUYBACK);
  console.log('CAKE_COLLECTOR=' + CAKE_COLLECTOR);
  console.log('CAKE_STRATEGY=' + CAKE_STRATEGY);
  console.log('AUTO_COLLECTOR=' + AUTO_COLLECTOR);
  console.log('AUTO_STRATEGY=' + AUTO_STRATEGY);
  console.log('PANTHER_BUYBACK=' + PANTHER_BUYBACK);
  console.log('PANTHER_STRATEGY=' + PANTHER_STRATEGY);
};
