// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import "../interface/IButterBridgeV3.sol";
import "../interface/IMOSV3.sol";
import "../interface/IMintableToken.sol";
import "../interface/IMapoExecutor.sol";
import "../interface/ISwapOutLimit.sol";
import "../interface/IButterReceiver.sol";
import "../interface/IFeeService.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {EvmDecoder} from "../lib/EvmDecoder.sol";
import {MessageInEvent} from "../lib/Types.sol";
//import "@mapprotocol/protocol/contracts/utils/Utils.sol";
//import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

abstract contract BridgeAbstract is
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    //AccessManagedUpgradeable,
    AccessControlEnumerableUpgradeable,
    IButterBridgeV3,
    IMOSV3
{
    address internal constant ZERO_ADDRESS = address(0);
    uint256 constant MINTABLE_TOKEN = 0x01;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public immutable selfChainId = block.chainid;

    uint256 private nonce;

    address internal wToken;
    address internal butterRouter;
    IFeeService internal feeService;
    ISwapOutLimit internal swapLimit;

    mapping(bytes32 => uint256) public orderList;

    mapping(address => uint256) public tokenFeatureList;
    mapping(uint256 => mapping(address => uint256)) public tokenMappingList;

    // service fee or bridge fee
    // address => (token => amount)
    mapping(address => mapping(address => uint256)) public feeList;

    error order_exist();
    error invalid_order_Id();
    error invalid_bridge_log();
    error invalid_pack_version();
    error in_amount_low();
    error token_call_failed();
    error token_not_registered();
    error zero_address();
    error not_contract();
    error zero_amount();
    error invalid_mos_contract();
    error invalid_message_fee();
    error length_mismatching();
    error bridge_same_chain();
    error only_upgrade_role();
    error not_support_value();
    error not_support_target_chain();
    error unsupported_message_type();

    event SetContract(uint256 _t, address _addr);
    event RegisterToken(address _token, uint256 _toChain, bool _enable);
    event UpdateToken(address token, uint256 feature);
    event WithdrawFee(address receiver, address token, uint256 amount);
    event GasInfo(bytes32 indexed orderId, uint256 indexed executingGas, uint256 indexed executedGas);

    event MessageTransfer(
        address initiator,
        address referrer,
        address sender,
        bytes32 orderId,
        bytes32 transferId,
        address feeToken,
        uint256 fee
    );

    receive() external payable {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _wToken, address _defaultAdmin) public initializer {
        _checkAddress(_wToken);
        _checkAddress(_defaultAdmin);
        __Pausable_init();
        __ReentrancyGuard_init();
        //__AccessManaged_init(_authority);
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(MANAGER_ROLE, _defaultAdmin);
        _grantRole(UPGRADER_ROLE, _defaultAdmin);
        wToken = _wToken;
    }

    // --------------------------------------------- manage ----------------------------------------------
    function trigger() external onlyRole(MANAGER_ROLE) {
        paused() ? _unpause() : _pause();
    }

    function registerTokenChains(
        address _token,
        uint256[] memory _toChains,
        bool _enable
    ) external onlyRole(MANAGER_ROLE) {
        if (!_isContract(_token)) revert not_contract();
        for (uint256 i = 0; i < _toChains.length; i++) {
            uint256 toChain = _toChains[i];
            uint256 enable = _enable ? 0x01 : 0x00;
            tokenMappingList[toChain][_token] = enable;
            emit RegisterToken(_token, toChain, _enable);
        }
    }

    function updateTokens(address[] calldata _tokens, uint256 _feature) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenFeatureList[_tokens[i]] = _feature;
            emit UpdateToken(_tokens[i], _feature);
        }
    }

    // --------------------------------------------- external view -------------------------------------------
    function isMintable(address _token) external view returns (bool) {
        return _isMintable(_token);
    }

    function getOrderStatus(
        uint256,
        uint256 _blockNum,
        bytes32 _orderId
    ) external view virtual override returns (bool exists, bool verifiable, uint256 nodeType) {}

    function getMessageFee(
        uint256 _toChain,
        address _feeToken,
        uint256 _gasLimit
    ) external view returns (uint256 fee, address receiver) {
        (fee, receiver) = _getMessageFee(_toChain, _feeToken, _gasLimit);
    }

    // --------------------------------------------- external ---------------------------------------------
    function withdrawFee(address receiver, address token) external payable {
        uint256 amount = feeList[receiver][token];
        if (amount > 0) {
            _tokenTransferOut(token, receiver, amount, true, false);
        }
        emit WithdrawFee(receiver, token, amount);
    }

    function transferOut(
        uint256 _toChain,
        bytes memory _messageData,
        address _feeToken
    ) external payable virtual override returns (bytes32 orderId) {}

    function swapOutToken(
        address _sender, // initiator address
        address _token, // src token
        bytes memory _to,
        uint256 _amount,
        uint256 _toChain, // target chain id
        bytes calldata _swapData
    ) external payable virtual override returns (bytes32 orderId) {}

    function depositToken(
        address _token,
        address to,
        uint256 _amount
    ) external payable virtual returns (bytes32 orderId) {}

    // --------------------------------------------- internal ---------------------------------------------

    function _transferOut(
        uint256 _fromChain,
        uint256 _toChain,
        bytes memory _messageData,
        address _feeToken
    ) internal virtual returns (MessageData memory msgData) {
        if (_toChain == _fromChain) revert bridge_same_chain();

        msgData = abi.decode(_messageData, (MessageData));
        if (msgData.value != 0) revert not_support_value();
        if (msgData.msgType != MessageType.MESSAGE) revert unsupported_message_type();

        (uint256 amount, address receiverFeeAddress) = _getMessageFee(_toChain, _feeToken, msgData.gasLimit);

        _tokenTransferIn(_feeToken, msg.sender, amount, false, false);
        feeList[receiverFeeAddress][_feeToken] += amount;
    }

    function _messageIn(MessageInEvent memory _inEvent, bool _gasleft) internal {
        address to = _fromBytes(_inEvent.to);
        uint256 gasLimit = _inEvent.gasLimit;

        uint256 executingGas = gasleft();
        if (_gasleft) {
            gasLimit = executingGas;
        }
        if (!_isContract(to)) {
            return _storeMessageData(_inEvent, bytes("NotContract"));
        }

        try
            IMapoExecutor(to).mapoExecute{gas: gasLimit}(
                _inEvent.fromChain,
                _inEvent.toChain,
                _inEvent.from,
                _inEvent.orderId,
                _inEvent.swapData
            )
        {
            emit MessageIn(
                _inEvent.orderId,
                _inEvent.fromChain,
                ZERO_ADDRESS,
                0,
                to,
                _inEvent.from,
                bytes(""),
                true,
                bytes("")
            );
        } catch (bytes memory reason) {
            emit GasInfo(_inEvent.orderId, executingGas, gasleft());
            _storeMessageData(_inEvent, reason);
        }
    }

    function _swapIn(MessageInEvent memory _inEvent) internal {
        address outToken = _inEvent.token;
        address to = _fromBytes(_inEvent.to);
        if (_inEvent.swapData.length > 0 && _isContract(to)) {
            // if swap params is not empty, then we need to do swap on current chain
            _tokenTransferOut(_inEvent.token, to, _inEvent.amount, false, false);
            try
                IButterReceiver(to).onReceived(
                    _inEvent.orderId,
                    _inEvent.token,
                    _inEvent.amount,
                    _inEvent.fromChain,
                    _inEvent.from,
                    _inEvent.swapData
                )
            {} catch {}
        } else {
            // transfer token if swap did not happen
            _tokenTransferOut(_inEvent.token, to, _inEvent.amount, true, false);
            if (_inEvent.token == wToken) outToken = ZERO_ADDRESS;
        }
        emit MessageIn(
            _inEvent.orderId,
            _inEvent.fromChain,
            outToken,
            _inEvent.amount,
            to,
            _inEvent.from,
            bytes(""),
            true,
            bytes("")
        );
    }

    function _tokenTransferIn(
        address _token,
        address _from,
        uint256 _amount,
        bool _wrap,
        bool _checkBurn
    ) internal returns (address inToken) {
        inToken = _token;
        if (_token == ZERO_ADDRESS) {
            if (msg.value < _amount) revert in_amount_low();
            if (_wrap) {
                _safeDeposit(wToken, _amount);
                inToken = wToken;
            }
        } else {
            _safeTransferFrom(_token, _from, address(this), _amount);
            if (_checkBurn) {
                _checkAndBurn(_token, _amount);
            }
        }
    }

    function _tokenTransferOut(address _token, address _receiver, uint256 _amount, bool _unwrap, bool _checkMint) internal {
        if (_token == ZERO_ADDRESS) {
            _safeTransferNative(_receiver, _amount);
        }
        else if (_token == wToken && _unwrap) {
            _safeWithdraw(wToken, _amount);
            _safeTransferNative(_receiver, _amount);
        } else {
            if (selfChainId == 728126428 && _token == 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C) {
                // Tron USDT
                _token.call(abi.encodeWithSelector(0xa9059cbb, _receiver, _amount));
            } else {
                if (_checkMint) {
                    _checkAndMint(_token, _amount);
                }
                _safeTransfer(_token, _receiver, _amount);
            }
        }
    }

    function _notifyLightClient(uint256 _chainId) internal virtual {}

    function _messageOut(
        bool _relay,
        MessageType _type,
        uint256 _gasLimit,
        address _from,
        address _token, // src token
        uint256 _amount,
        address _mos,
        uint256 _toChain, // target chain id
        bytes memory _to,
        bytes memory _message
    ) internal returns (bytes32 orderId) {
        uint256 header = EvmDecoder.encodeMessageHeader(_relay, uint8(_type));
        if (_type == MessageType.BRIDGE) {
            _checkLimit(_amount, _toChain, _token);
            _checkBridgeable(_token, _toChain);
        }
        uint256 fromChain = selfChainId;
        if (_toChain == fromChain) revert bridge_same_chain();

        address from = (msg.sender == butterRouter) ? _from : msg.sender;

        uint256 chainAndGasLimit = _getChainAndGasLimit(fromChain, _toChain, _gasLimit);

        orderId = _getOrderId(fromChain, _toChain, from, _to);

        bytes memory payload = abi.encode(header, _mos, _token, _amount, from, _to, _message);

        emit MessageOut(orderId, chainAndGasLimit, payload);

        _notifyLightClient(_toChain);
    }

    function _storeMessageData(MessageInEvent memory _outEvent, bytes memory _reason) internal {
        orderList[_outEvent.orderId] = uint256(
            keccak256(
                abi.encodePacked(
                    _outEvent.fromChain,
                    _outEvent.toChain,
                    _outEvent.token,
                    _outEvent.amount,
                    _outEvent.from,
                    _outEvent.to,
                    _outEvent.swapData
                )
            )
        );
        bytes memory payload = abi.encode(_outEvent.toChain, _outEvent.gasLimit, _outEvent.to, _outEvent.swapData);
        emit MessageIn(
            _outEvent.orderId,
            _outEvent.fromChain,
            _outEvent.token,
            _outEvent.amount,
            _fromBytes(_outEvent.to),
            _outEvent.from,
            payload,
            false,
            _reason
        );
    }

    function _getOrderId(
        uint256 _fromChain,
        uint256 _toChain,
        address _from,
        bytes memory _to
    ) internal returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), nonce++, _fromChain, _toChain, _from, _to));
    }

    function _getMessageFee(
        uint256 _toChain,
        address _feeToken,
        uint256 _gasLimit
    ) internal view returns (uint256 amount, address receiverAddress) {
        (amount, receiverAddress) = feeService.getServiceMessageFee(_toChain, _feeToken, _gasLimit);
        if (amount == 0) revert not_support_target_chain();
    }

    function _checkAddress(address _address) internal pure {
        if (_address == ZERO_ADDRESS) revert zero_address();
    }

    function _checkBridgeable(address _token, uint256 _chainId) internal view {
        if ((tokenMappingList[_chainId][_token] & 0x0F) != 0x01) revert token_not_registered();
    }

    function _checkAndBurn(address _token, uint256 _amount) internal {
        if (_isMintable(_token)) {
            IMintableToken(_token).burn(_amount);
        }
    }

    function _checkAndMint(address _token, uint256 _amount) internal {
        if (_isMintable(_token)) {
            IMintableToken(_token).mint(address(this), _amount);
        }
    }

    function _isMintable(address _token) internal view returns (bool) {
        return (tokenFeatureList[_token] & MINTABLE_TOKEN) == MINTABLE_TOKEN;
    }

    function _checkLimit(uint256 amount, uint256 tochain, address token) internal {
        if (address(swapLimit) != ZERO_ADDRESS) swapLimit.checkLimit(amount, tochain, token);
    }

    function _checkOrder(bytes32 _orderId) internal {
        if (orderList[_orderId] == 0x01) revert order_exist();
        orderList[_orderId] = 0x01;
    }

    function _getChainAndGasLimit(
        uint256 _fromChain,
        uint256 _toChain,
        uint256 _gasLimit
    ) internal pure returns (uint256 chainAndGasLimit) {
        chainAndGasLimit = ((_fromChain << 192) | (_toChain << 128) | _gasLimit);
    }

    // --------------------------------------------- utils ----------------------------------------------
    function _checkBytes(bytes memory b1, bytes memory b2) internal pure returns (bool) {
        return keccak256(b1) == keccak256(b2);
    }

    function _toBytes(address _a) internal pure returns (bytes memory) {
        return abi.encodePacked(_a);
    }

    function _fromBytes(bytes memory bys) internal pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        _checkCallResult(success, data);
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        _checkCallResult(success, data);
    }

    function _safeTransferNative(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(bytes(""));
        _checkCallResult(success, bytes(""));
    }

    function _safeWithdraw(address _wToken, uint _value) internal {
        (bool success, bytes memory data) = _wToken.call(abi.encodeWithSelector(0x2e1a7d4d, _value));
        _checkCallResult(success, data);
    }

    function _safeDeposit(address _wToken, uint _value) internal {
        (bool success, bytes memory data) = _wToken.call{value: _value}(abi.encodeWithSelector(0xd0e30db0));
        _checkCallResult(success, data);
    }

    function _checkCallResult(bool _success, bytes memory _data) internal pure {
        if (!_success || (_data.length != 0 && !abi.decode(_data, (bool)))) revert token_call_failed();
    }

    function _isContract(address _addr) internal view returns (bool) {
        return _addr.code.length != 0;
    }

    /** UUPS *********************************************************/
    function _authorizeUpgrade(address) internal view override {
        if (!hasRole(UPGRADER_ROLE, msg.sender)) revert only_upgrade_role();
    }

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
        // return _getImplementation();
    }
}
