// [DEPLOY WITH]
// npx hardhat deploy --network ethereum --tags Greeter --write true

import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  console.log('Deploying contracts')

  const kaaveContract = 'KAAVE'
  const discountedPriceOracleContract = 'DiscountedPriceOracle'
  const { deployer } = await getNamedAccounts()
  console.log('Deployer address', deployer)

  const kaaveDeployResult = await deploy(kaaveContract, {
    from: deployer,
    args: [], 
    log: true,
  })

  if (kaaveDeployResult.newlyDeployed) {
    console.log(
      `contract ${kaaveContract} deployed at ${kaaveDeployResult.receipt?.contractAddress} using ${kaaveDeployResult.receipt?.gasUsed} gas`
    )
  }

  const oracleDeployResult = await deploy(discountedPriceOracleContract, {
    from: deployer,
    args: [kaaveDeployResult.receipt?.contractAddress],
    log: true,
  })
  if (oracleDeployResult.newlyDeployed) {
    console.log(
      `contract ${discountedPriceOracleContract} deployed at ${oracleDeployResult.receipt?.contractAddress} using ${oracleDeployResult.receipt?.gasUsed} gas`
    )
  }


}

export default func
func.tags = ['Greeter']
