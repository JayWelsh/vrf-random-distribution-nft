let {networkConfig} = require('../helper-hardhat-config')

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = async ({
  getNamedAccounts,
  deployments,
}) => {

  const chainId = await getChainId()

  const { deploy, get, log } = deployments
  const { deployer } = await getNamedAccounts()

  let RandomNumberConsumer = await deployments.get('RandomNumberConsumer');

  let args;
  if (chainId == 1) {
    // Is a mainnet deployment, require deployer to explicitly set the below options
    args = [

    ]
  } else {
    // Use test config, as it is not a mainnet deployment
    // In this demo, we have a demo token called "Restore"
    let tokenFullName = "RESTORE";
    let tokenShortName = "RSTR"; // Token symbol (short name / ticker)
    let preRevealURI = "ipfs://QmTSbgfx6YTFZ4HXrKCwCRGqEJrRbGrP6eZhb3TNfjU11U/pending_reveal.json" // Metadata of token prior to random reveal
    let baseURI = "ipfs://QmTSbgfx6YTFZ4HXrKCwCRGqEJrRbGrP6eZhb3TNfjU11U/" // Base URI to use once reveal has occurred
    let suffixBaseURI = ".json" // Suffix to use along with {baseURI} + {tokenIdWithRandomOffset} + {suffix}, e.g. "ipfs://QmTSbgfx6YTFZ4HXrKCwCRGqEJrRbGrP6eZhb3TNfjU11U/" + "10" + ".json"  
    let supplyLimit = "8"; // Total token supply
    let mintingStartsInMinutesFromDeployment = 2;
    let mintingLengthMinutes = 3; // Using 15 minute minting length for easy testing of full process on testnet
    let ethPricePerToken = "0.001";
    let maxMintUnitsPerTx = "4"; // Max amount of tokens that can be minted/purchased in a single Ethereum transaction
    let vrfProvider = RandomNumberConsumer.address;

    // Derive some args from the human readable data above
    let weiPricePerToken = ethers.utils.parseUnits(ethPricePerToken, 'ether');
    let mintingStartTimeUnix = (60 * mintingStartsInMinutesFromDeployment) + (new Date(new Date().setMilliseconds(0)).setSeconds(0) / 1000);
    let mintingEndTimeUnix = mintingStartTimeUnix + (mintingLengthMinutes * 60);
    args = [
      tokenFullName,
      tokenShortName, 
      preRevealURI, 
      baseURI, 
      suffixBaseURI, 
      supplyLimit, 
      mintingStartTimeUnix.toString(), // The unix timestamp at which minting starts
      mintingEndTimeUnix.toString(), // The unix timestamp at which the minting ends
      weiPricePerToken, // Price in wei per token
      maxMintUnitsPerTx,
      vrfProvider,
    ]
  }

  if(args) {

    // Deploy the reference contract
    const vrf721NFTClonable = await deploy('OffsetVariantVRF721NFTClonable', {
      from: deployer,
      log: true
    })
    let nftAddress = vrf721NFTClonable.address;

    // Initialize the reference contract
    const vrf721NFTClonableAttached = await ethers.getContractAt('OffsetVariantVRF721NFTClonable', vrf721NFTClonable.address)
    await vrf721NFTClonableAttached.initialize(...args);

    // Deploy clone factory
    const vrf721NFTCloneFactory = await deploy('OffsetVariantVRF721NFTCloneFactory', {
      from: deployer,
      args: [
        nftAddress
      ],
      log: true
    })

    // Deploy clone via clone factory
    const cloneFactoryAttached = await ethers.getContractAt('OffsetVariantVRF721NFTCloneFactory', vrf721NFTCloneFactory.address)
    let txCloneFactory = await cloneFactoryAttached.newVRF721Clone(...args);
    let receipt = await txCloneFactory.wait();

    console.log({receipt})

    console.log({gasUsed: receipt.gasUsed.toString()})

    // Add the NFT address to the list of approved randomness requesters
    const randomNumberConsumer = await ethers.getContractAt('RandomNumberConsumer', RandomNumberConsumer.address)
    let tx = await randomNumberConsumer.setRandomnessRequesterApproval(nftAddress, true);
    tx.wait();

    if([1, 4, 5, 42].indexOf(Number(chainId)) > -1) {
      // Run etherscan verification on mainnet, rinkeby, goerli & kovan
      await sleep(45000);
      await hre.run("verify:verify", {
          address: vrf721NFTClonable.address,
          constructorArguments: args,
      })
    }
  } else {
    console.error("Please set your token deployment arguments")
  }

}

module.exports.tags = ['all', 'vrf']
