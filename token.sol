// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/IERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/Address.sol";
import "./lib/Ownable.sol";
import "./lib/PancakeSwap.sol";

import "./Raffle.sol";

contract Token is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 10 ** 6 * 10 ** 6 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "Rafflection";
    string private _symbol = "RAFF";
    uint8 private _decimals = 9;

    uint256 public numTokensSellToAddToLiquidity = 500 * 10**6 * 10**9;
    uint256 public numTokensToAddToRaffle = 500 * 10**6 * 10**9;

    uint256 public balanceForRaffle;
    uint256 public balanceForLiquidity;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    IPancakeSwapV2Router02 private immutable PancakeSwapV2Router;
    address private immutable PancakeSwapV2Pair;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    Raffle raffleContract;
    bool private raffleContractSet = false;
    bool public raffleFeesEnabled = false;

    bool public feesEnabled = true;

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(IPancakeSwapV2Router02 PancakeSwapRouter) {
        _rOwned[_msgSender()] = _rTotal;

        IPancakeSwapV2Router02 _PancakeSwapV2Router = IPancakeSwapV2Router02(PancakeSwapRouter);

        PancakeSwapV2Pair = IPancakeSwapV2Factory(_PancakeSwapV2Router.factory())
            .createPair(address(this), _PancakeSwapV2Router.WETH());

        PancakeSwapV2Router = _PancakeSwapV2Router;

        _isExcluded[address(this)] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflect(uint256 tAmount) private {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeAccount(address account) external onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function setFeesEnabled(bool enabled) public onlyOwner {
        feesEnabled = enabled;
    }

    function setRaffleFeesEnabled(bool enabled) public onlyOwner {
        raffleFeesEnabled = enabled;
    }

    function includeAccount(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function setRaffleContract(Raffle _raffle) public onlyOwner() {
        raffleContract = Raffle(_raffle);
        raffleContractSet = true;
        raffleFeesEnabled = true;
    }

    receive() external payable {}

    function swapAndLiquify(uint256 toAdd) private lockTheSwap {
        _enableAllFess(false);

        // split the contract balance into halves
        uint256 half = toAdd.div(2);
        uint256 otherHalf = toAdd.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to PancakeSwap
        addLiquidity(otherHalf, newBalance);

        // remove liquidity transfered from balance
        balanceForLiquidity = balanceForLiquidity.sub(toAdd);

        _enableAllFess(true);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the PancakeSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PancakeSwapV2Router.WETH();

        _approve(address(this), address(PancakeSwapV2Router), tokenAmount);

        // make the swap
        PancakeSwapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp.add(10000)
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(PancakeSwapV2Router), tokenAmount);

        // add the liquidity
        PancakeSwapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool overMinTokenBalance =
            balanceForLiquidity >= numTokensSellToAddToLiquidity;
        if (
            swapAndLiquifyEnabled &&
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            sender != PancakeSwapV2Pair
        ) {
            //add liquidity
            swapAndLiquify(numTokensSellToAddToLiquidity);
        }

        // token swapping

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (raffleContractSet) {
            raffleContract.updateBalances(
                sender,
                recipient,
                balanceOf(sender),
                balanceOf(recipient),
                _tTotal.sub(balanceOf(BURN_ADDRESS))
            );
        }

        bool overMinRafBalance = balanceForRaffle >= numTokensToAddToRaffle;
        if (
            raffleContractSet &&
            raffleFeesEnabled &&
            overMinRafBalance &&
            raffleContractSet
        ) {
            // transfer to raffle contract
            _transferToRaffle(numTokensToAddToRaffle);
        }
    }

    function _transferToRaffle(uint256 toAdd) private {
        _enableAllFess(false);
        _transfer(address(this), address(raffleContract), toAdd);
        balanceForRaffle = balanceForRaffle.sub(toAdd);
        _enableAllFess(true);
    }

    function enableAllFeels(bool enabled) public onlyOwner {
        _enableAllFess(enabled);
    }

    function _enableAllFess (bool enabled) private {
        feesEnabled = enabled;
        swapAndLiquifyEnabled = enabled;
        raffleFeesEnabled = enabled;
    }

    function _takeLiquidityAndRaffle(uint256 tLiquidity, uint256 tRaffle)
        private
    {
        uint256 currentRate = _getRate();
        uint256 tTotalFees = tLiquidity.add(tRaffle);
        uint256 rTotalFees = tTotalFees.mul(currentRate);

        _rOwned[address(this)] = _rOwned[address(this)].add(rTotalFees);
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tTotalFees);

        balanceForLiquidity = balanceForLiquidity.add(tLiquidity);
        balanceForRaffle = balanceForRaffle.add(tRaffle);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tRaffle
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidityAndRaffle(tLiquidity, tRaffle);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tRaffle
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidityAndRaffle(tLiquidity, tRaffle);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tRaffle
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidityAndRaffle(tLiquidity, tRaffle);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tRaffle
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidityAndRaffle(tLiquidity, tRaffle);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tRaffle
        ) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) =
            _getRValues(tAmount, tFee, tLiquidity, tRaffle, _getRate());
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee,
            tLiquidity,
            tRaffle
        );
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = 0;
        uint256 tLiquidity = 0;
        uint256 tRaffle = 0;

        if (feesEnabled) {
            tFee = tAmount.div(25); // 4%
        }

        if (swapAndLiquifyEnabled) {
            tLiquidity = tAmount.div(50); // 2%
        }

        if (raffleFeesEnabled) {
            tRaffle = tAmount.div(50);
        }

        uint256 tTransferAmount =
            tAmount.sub(tFee).sub(tLiquidity).sub(tRaffle);
        return (tTransferAmount, tFee, tLiquidity, tRaffle);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tLiquidity,
        uint256 tRaffle,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rRaffle = tRaffle.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity).sub(rRaffle);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
}