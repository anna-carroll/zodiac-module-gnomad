// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.6;

import "@gnosis.pm/zodiac/contracts/core/Module.sol";

interface IXAppConnectionManager {
    function isReplica(address _replica) external view returns (bool);
}

contract GnomadModule is Module {
    event GnomadModuleSetup(
        address indexed initiator,
        address indexed owner,
        address indexed avatar,
        address target
    );

    IXAppConnectionManager public manager;
    bytes32 public controller;
    uint32 public controllerDomain;

    /// @param _owner Address of the  owner
    /// @param _avatar Address of the avatar (e.g. a Safe)
    /// @param _target Address of the contract that will call exec function
    /// @param _manager Address of the Nomad xAppConnectionManager contract.
    /// @param _controller Address of the controller which is authorized to send messages to the module from a remote domain.
    /// @param _controllerDomain Domain of the controller which is authorized to send messages to the module.
    // Domains are defined as unique identifiers within Nomad for a domain (chain, L1, L2, sidechain, rollup, etc).
    constructor(
        address _owner,
        address _avatar,
        address _target,
        address _manager,
        bytes32 _controller,
        uint32 _controllerDomain
    ) {
        bytes memory initParams = abi.encode(
            _owner,
            _avatar,
            _target,
            _manager,
            _controller,
            _controllerDomain
        );
        setUp(initParams);
    }

    function setUp(bytes memory initParams) public override {
        (
            address _owner,
            address _avatar,
            address _target,
            address _manager,
            bytes32 _controller,
            uint32 _controllerDomain
        ) = abi.decode(initParams, (address, address, address, address, bytes32, uint32));
        __Ownable_init();

        require(_avatar != address(0), "Avatar can not be zero address");
        require(_target != address(0), "Target can not be zero address");
        avatar = _avatar;
        target = _target;
        manager = IXAppConnectionManager(_manager);
        controller = _controller;
        controllerDomain = _controllerDomain;

        transferOwnership(_owner);

        emit GnomadModuleSetup(msg.sender, _owner, _avatar, _target);
    }

    /// @dev Check that the replica, origin, and controller are valid
    modifier onlyValid(address _caller, uint32 _origin, bytes32 _sender) {
        require(manager.isReplica(_caller), "caller must be a valid replica");
        require(isController(_sender, _origin), "Unauthorized controller");
        _;
    }

    /// @dev Set the Replica contract address
    /// @param _manager Address of the Xapp manager contract
    /// @notice This can only be called by the owner
    function setManager(IXAppConnectionManager _manager) public onlyOwner {
        require(manager != _manager, "Replica address already set to this");
        manager = _manager;
    }

    /// @dev Set the approved chainId
    /// @param _origin ID of the approved network
    /// @notice This can only be called by the owner
    function setControllerDomain(uint32 _controllerDomain) public onlyOwner {
        require(controllerDomain != _controllerDomain, "chainId already set to this");
        controllerDomain = _controllerDomain;
    }

    /// @dev Set the controller address
    /// @param _controller Set the address of controller on the other side of the bridge
    /// @notice This can only be called by the owner
    function setController(bytes32 _controller) public onlyOwner {
        require(controller != _controller, "controller already set to this");
        controller = _controller;
    }

    /// @notice Handle Nomad messages
    /// For all non-Governor chains to handle messages
    /// sent from the Governor chain via Nomad.
    /// Governor chain should never receive messages,
    /// because non-Governor chains are not able to send them
    /// @param _origin The domain (of the Governor Router)
    /// @param _sender The message sender (must be the Governor Router)
    /// @param _message The message
    function handle(
        uint32 _origin,
        uint32, // _nonce (unused)
        bytes32 _sender,
        bytes memory _message
    ) external onlyValid(msg.sender, _origin, _sender) {
        (
            address _to,
            uint256 _value,
            bytes memory _data,
            Enum.Operation _operation
        ) = abi.decode(_message, (address, uint256, bytes, Enum.Operation));
        executeTransaction(_to, _value, _data, _operation);
    }

    /// @dev Executes a transaction initated by the Nomad Bridge
    /// @param to Target of the transaction that should be executed
    /// @param value Wei value of the transaction that should be executed
    /// @param data Data of the transaction that should be executed
    /// @param operation Operation (Call or Delegatecall) of the transaction that should be executed
    function executeTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal {
        require(exec(to, value, data, operation), "Module transaction failed");
    }

    function isController(bytes32 _controller, uint32 _controllerDomain) public view returns (bool) {
        return _controller == controller && _controllerDomain == controllerDomain;
    }
}
