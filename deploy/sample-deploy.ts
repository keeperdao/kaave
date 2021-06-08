// [DEPLOY WITH]
// npx hardhat deploy --network ethereum --tags Greeter --write true

import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  console.log('Deploying contract')

  const contract = 'Greeter'
  const { deployer } = await getNamedAccounts()
  console.log('Deployer address', deployer)

  const deployResult = await deploy(contract, {
    from: deployer,
    args: ["Hello World!"], 
    log: true,
  })

  if (deployResult.newlyDeployed) {
    console.log(
      `contract ${contract} deployed at ${deployResult.receipt?.contractAddress} using ${deployResult.receipt?.gasUsed} gas`
    )
  }
}

export default func
func.tags = ['Greeter']
