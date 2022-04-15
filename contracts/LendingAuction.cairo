# Twitter : 0xKermo
# https://www.youtube.com/watch?v=i3SkJ11bTOk
 
%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (
    assert_le,
    assert_lt,
    assert_not_equal,
    assert_not_zero,
)

from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_le,
    uint256_lt,
)
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_block_timestamp,
    get_contract_address,
)

from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.utils.constants import FALSE, TRUE

const DENOMINATOR = 10000

struct LoanAuction:
    member borrower : felt
    member topLender : felt
    member colleteralAddress : felt 
    member colleteralId : Uint256
    member loanCurrency : felt # token address to be accepted
    member loanAmount : felt  
    member loanRepaymentAmount : felt   
    member auctionDepositAmount : felt
    member minDecrementFactorNumerator : felt
    member auctionEndTime : felt
    member loanRepaymentDeadline : felt
end

# A map from loan id to the corresponding loan auction.
@storage_var
func loanAuctions(loanId : felt) -> (res : LoanAuction):
end

# loan auction count
@storage_var
func num_auctions() -> (res:felt):
end

# start loan auction
@external
func startAuction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        colleteralAddress: felt,
        colleteralId: Uint256,
        loanCurrency : felt,
        loanAmount : felt,
        maxLoanRepaymentAmount : felt,
        auctionDepositAmount : felt,
        minDecrementFactorNumerator : felt,
        auctionEndTime : felt,
        loanRepaymentDeadline : felt,
    ) -> (loanAuctionId : felt):

    alloc_locals

    let (currentBlockTime) = get_block_timestamp()
    let (current_auction_id) = num_auctions.read()

    with_attr error_message("Creating ended auction"):
        assert_lt(currentBlockTime, auctionEndTime)
    end

    with_attr error_message("Cant repay before auction end"):
        assert_lt(auctionEndTime, loanRepaymentDeadline)
    end

    with_attr error_message("Must deposit"):
        is_not_zero(auctionDepositAmount)
    end

    with_attr error_message("Deposit cant exceed loan"):
        assert_le(auctionDepositAmount , loanAmount)
    end

    with_attr error_message("Repayment less than loan"):
        assert_lt(loanAmount, maxLoanRepaymentAmount)
    end

    with_attr error_message("Factor must be <1"):
        assert_lt(minDecrementFactorNumerator , DENOMINATOR)
    end

    with_attr error_message("Factor must be positive"):
        assert_lt(0, minDecrementFactorNumerator)
    end

    let (local caller) = get_caller_address()
    let (local contractAddress) = get_contract_address()

    IERC721.transferFrom(colleteralAddress,caller,contractAddress,colleteralId)

    let _loanAuctions = LoanAuction(
        borrower = caller,
        topLender = 0,
        colleteralAddress = colleteralAddress,
        colleteralId = colleteralId,
        loanCurrency = loanCurrency,
        loanAmount = loanAmount,
        loanRepaymentAmount = maxLoanRepaymentAmount,
        auctionDepositAmount = auctionDepositAmount,
        minDecrementFactorNumerator = minDecrementFactorNumerator,
        auctionEndTime = auctionEndTime,
        loanRepaymentDeadline = loanRepaymentDeadline,
    )
    
    loanAuctions.write(current_auction_id,_loanAuctions)
    let next_auction_id = current_auction_id + 1
    num_auctions.write(next_auction_id)
    return (current_auction_id)
end



@external
func cancelAuction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        loanAuctionId : felt,
    ):
    alloc_locals

    let (local _loanAuctions) = loanAuctions.read(loanAuctionId)
    let (caller) = get_caller_address()
    let (contractAddress) = get_contract_address()

    with_attr error_message("This is not your auction, Get out!"):
        assert _loanAuctions.borrower = caller
    end

    with_attr error_message("Can not cancel active auction"):
        assert _loanAuctions.topLender = 0
    end
    
    IERC721.transferFrom(_loanAuctions.colleteralAddress,contractAddress,caller,_loanAuctions.colleteralId)
    return ()
end


@external
func bid{
      syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        loanAuctionId : felt,
        repayAmount : felt 
    ):

    alloc_locals

    let (local _loanAuctions) = loanAuctions.read(loanAuctionId)
    let (local caller) = get_contract_address()
    let (local contractAddress) = get_contract_address()

    with_attr error_message("Cant your bid auction"):
       assert_not_equal(caller ,_loanAuctions.borrower)
    end

    with_attr error_message("Repayment less than loan"):
        assert_lt(_loanAuctions.loanAmount , repayAmount)
    end

    with_attr error_message("Must bid within limit"):
        assert_le(repayAmount, _loanAuctions.loanRepaymentAmount)
    end

    assert_not_zero(_loanAuctions.topLender)
    
    let total = _loanAuctions.loanAmount + 
    ((_loanAuctions.loanRepaymentAmount - _loanAuctions.loanAmount) *
     _loanAuctions.minDecrementFactorNumerator) / 
     DENOMINATOR

    with_attr error_message("Must bid better"):
        assert_lt(repayAmount, total)
    end

    if _loanAuctions.topLender != 0:
        IERC20.transferFrom(
        _loanAuctions.loanCurrency,
        caller,
        _loanAuctions.topLender,
        Uint256(_loanAuctions.auctionDepositAmount,0),
        )
    else:
        IERC20.transferFrom(
        _loanAuctions.loanCurrency,
        caller,
        contractAddress,
        Uint256(_loanAuctions.auctionDepositAmount,0),
        )
    end
    _loanAuctions.topLender = caller
    return ()
end


@external
func getLoan{
      syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        loanAuctionId : felt,
    )-> (bool: felt):

    alloc_locals

    let (local _loanAuctions) = loanAuctions.read(loanAuctionId)
    let (local caller) = get_caller_address()
    let (local contractAddress) = get_contract_address()
    let (local blokTime) = get_block_timestamp()

    with_attr error_message("Not your actuion"):
        assert _loanAuctions.borrower = caller
    end
    
    with_attr error_message("Auction not completed"):
        assert_lt(_loanAuctions.auctionEndTime, blokTime)
    end

    with_attr error_message("Loan already taken"):
        assert_lt(0,_loanAuctions.auctionDepositAmount)
    end
    let (collateralOwner) =  IERC721.ownerOf(contract_address = _loanAuctions.colleteralAddress, tokenId = _loanAuctions.colleteralId) 
    
    with_attr error_message("Missing collateral"):
        assert collateralOwner = contractAddress
    end

    with_attr error_message("Past repayment deadline"):
        assert_lt(blokTime,_loanAuctions.loanRepaymentDeadline)
    end

    let (remaining) = IERC20.allowance(_loanAuctions.loanCurrency,_loanAuctions.topLender,contractAddress)
    let res :felt = uint256_le(Uint256(_loanAuctions.loanAmount -_loanAuctions.auctionDepositAmount ,0),remaining)
    

    if res == 1:
        IERC20.transferFrom(
        _loanAuctions.loanCurrency,
        _loanAuctions.topLender,
        caller,
        Uint256(_loanAuctions.loanAmount - _loanAuctions.auctionDepositAmount,0),
        )
        _loanAuctions.auctionDepositAmount = 0
        return (TRUE)

    else:
        IERC721.transferFrom(
        _loanAuctions.colleteralAddress,
        contractAddress,
        _loanAuctions.borrower,
        _loanAuctions.colleteralId,
        )
        return (FALSE)
    end
end

