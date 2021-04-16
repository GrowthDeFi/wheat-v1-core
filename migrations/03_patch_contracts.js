const Patcher1 = artifacts.require('Patcher1');
const LibPatcher1_1 = artifacts.require('LibPatcher1_1');
const LibPatcher1_2 = artifacts.require('LibPatcher1_2');

module.exports = async (deployer, network, [account]) => {
  console.log('Preparing the patcher1 contract...');
  await deployer.deploy(LibPatcher1_1);

  await deployer.deploy(LibPatcher1_2);

  deployer.link(LibPatcher1_1, Patcher1);
  deployer.link(LibPatcher1_2, Patcher1);
  await deployer.deploy(Patcher1);

  if (['development'].includes(network)) {
    console.log('Performing the deploy...');
    const contract = await Patcher1.deployed();
    await contract.deploy();
  }
};
