# kAave

This is the inaugural Solidity development challenge created for KeeperDAO Labs.

## Challenge:
Implement the `preempt()` function in the KAave.sol contract. This function must simulate the `liquidationCall()` function in Aave.

### Bonus:
Test the function by taking over the Aave oracle using `hardhat_impersonateAccount`. Change token prices and call this function.

### Background:

DeFi lending uses collateral to ensure repayment is always possible. A borrower may open a loan, called a 'position', after depositing sufficient collateral to cover it. The specific amount that can be borrowed is determined by a [loan-to-value (LTV) ratio](https://docs.Aave.com/risk/asset-risk/risk-parameters#loan-to-value). The value of the collateral and borrowed assets can change over time. DeFi lending protocols use price oracles to track the value of both. If the value of a positions collateral drops below a certain amount, the position will be considered risky. This risk is summarized as a [health factor](https://docs.Aave.com/risk/asset-risk/risk-parameters#health-factor) for the position. If the health factor drops below 1, the position may be liquidated to maintain solvency. 

To prevent liquidation, the borrower must either deposit more collateral or repay a portion of the loan to restore the health factor. Otherwise, the position's collateral becomes available for purchase, usually at a discount. This sale of discounted collateral is known as "liquidation", and the proceeds of this sale are used by the lending protocol to safely repay the loan. Most DeFi lending protocols, including Aave, Compound, MakerDAO, etc, follow this pattern.

When a position's collateral becomes available for liquidation, any EOA can submit a transaction to liquidate all or part of the position. Because the collateral is being offered at a discount, this is a profitable enterprise for those with the liquidity and speed to execute these transactions, such as keepers. 

However when keepers compete, it can result in a gas auction or other mechanisms that extract MEV from their profitable liquidation. This thins the profit margin of the keepers, and may even prevent keepers from participating in a liquidation, increasing price and solvency risk for the borrower and the lending protocol alike.

We at KeeperDAO build integrations called Hiding Vaults, which wrap DeFi lending positions in a special smart contract to ensure that if a liquidation is necessary, it can be carried out by a KeeperDAO keeper in a way that minimizes MEV extraction. kAave is the Hiding Vault for the Aave lending protocol. 

The kAave contract allows KeeperDAO's Just-In-Time Underwriter (JITU) to both deposit additional collateral to protect a position, and to perform a pre-emptive liquidation that prevents the collateral being auctioned on the open market. The combination of these features reduce the borrower's chance of being liquidated, and ensures better execution of the liquidation if it is ultimately carried out.

The JITU contract calls the `preempt()` function to perform a preemptive liquidation when the value of the position's original collateral (i.e. excluding the extra collateral provided by the JITU contract) would make it vulnerable to liquidation. Therefore `preempt()` should simulate the `liquidationCall` function, in particular: 
* determine whether the underlying position would be eligible for liquidation without the extra collateral
* repay the loan 
* seize the collateral

Study the `liquidationCall()` function and workflow in Aave as a starting point. Try to implement the `preempt()` function with the least number of contract calls possible.

### Rules:

* No plagarism 
* No outsourcing
* Clean, well-documented code
* Publish the project code with [MIT License](https://opensource.org/licenses/MIT)

### Bounty:

* First working submission: 20 ROOK (+5 ROOK for bonus)
* Second working submission: 10 ROOK (+5 ROOK for bonus)

and an interview to work as a Solidity Developer @ KeeperDAO.

### Submission:

Create a fork of this repo, implement the preempt() function and create a PR back to the main repo.

References

[Aave Introduction](https://docs.aave.com/developers/)

[Aave V2](https://github.com/aave/protocol-v2)

