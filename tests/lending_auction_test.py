"""LendingAuction.cairo test file."""
import os

import pytest
from starkware.starknet.testing.starknet import Starknet
from utils import Signer, uint, str_to_felt, to_uint
import time

# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "LendingAuction.cairo")
ERC20_FILE = os.path.join("contracts", "mock", "ERC20.cairo")

ONE_DAY = 86400 # number of seconds in a day
user = Signer(442352433)
# random token IDs
TOKENS = [to_uint(5042), to_uint(793)]
# test token
TOKEN = TOKENS[0]

@pytest.fixture(scope="module")
async def contract_factory():
    # Deploy the contracts
    starknet = await Starknet.empty()
    lendingContract = await starknet.deploy(CONTRACT_FILE)
    account1 = await starknet.deploy(
        "openzeppelin/account/Account.cairo",
        constructor_calldata=[signer.public_key],
    )
    erc20 = await starknet.deploy(
        source=ERC20_FILE,
        constructor_calldata=[
            str_to_felt('ERC20'),
            str_to_felt('ERC20'),
            18,
            *uint(100000),
            user_account.contract_address
        ]
    )

    erc721 = await starknet.deploy(
        "openzeppelin/token/erc721/ERC721_Mintable_Burnable.cairo",
        constructor_calldata=[
            str_to_felt("Non Fungible Token"),  
            str_to_felt("NFT"),                 
            user_account.contract_address           
        ]
    )

      # Mint tokens to user_account
    for token in TOKENS:
        await signer.send_transaction(
            account=account1,
            to=erc721.contract_address,
            selector_name="mint",
            calldata=[user_account.contract_address, *token]
        )
    
      # Approve the tokens for the lending auction contract
    await user.send_transaction(
        account=user_account,
        to=erc721.contract_address,
        selector_name="setApprovalForAll",
        calldata=[lendingContract.contract_address, TRUE]
    )
    await user.send_transaction(
        account=user_account,
        to=erc20.contract_address,
        selector_name="approve",
        calldata=[lendingContract.contract_address,*uint(10000) ]
    )

    return lendingContract, account1, erc721, erc20

@pytest.mark.asyncio
async def startAuction():
    """Auction start method."""

    lendingContract,user_account, erc721,erc20= await contract_factory()

  
    timeStamp = time.time()

    colleteralAddress = erc721.contract_address,
    colleteralId = *TOKEN,
    loanCurrency =mock_erc20.contract_address,
    loanAmount =100,
    maxLoanRepaymentAmount= 110,
    auctionDepositAmount = 90,
    minDecrementFactorNumerator= 1000,
    auctionEndTime = (timeStamp + ONE_DAY) / 2,
    loanRepaymentDeadline =timeStamp + ONE_DAY,
    # Auction start
    auctionId = await lendingContract.startAuction(colleteralAddress,colleteralId,loanCurrency,
    loanAmount, maxLoanRepaymentAmount, auctionDepositAmount, minDecrementFactorNumerator, auctionEndTime,
    loanRepaymentDeadline).invoke()

    nextAuctionId = await lendingContract.num_auctions().call().result
    nftOwner =  await erc721.ownerOf(TOKEN).call()
    
    # Is nft given as collateral to the contract? 
    assert nftOwner.result == lendingContract.contract_address
    assert to_uint(auctionId.result) == to_uint(nextAuctionId-1)


@pytest.mark.asyncio
async def auctionFactory():

    lendingContract, user_account, erc721, erc20= await contract_factory()

    await lendingContract.cancelAuction(1).invoke()
    nftOwner =  await erc721.ownerOf(TOKEN).call()
    assert nftOwner.result == user_account.contract_address
