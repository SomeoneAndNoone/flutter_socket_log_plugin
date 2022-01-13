part of flutter_socket_log_plugin;

class _FlutterSocketLogPluginImpl extends FlutterSocketLogPlugin {
  bool isInitialized = false;
  List<protos.LogTag> allLogTags = [];
  List<protos.LogLevel> allLogLevels = [];
  late String appName;
  ServerSocket? _server;

  final BehaviorSubject<Socket?> _clientSubject = BehaviorSubject.seeded(null);

  @override
  Stream<Socket?> get _clientStream => _clientSubject.stream;

  Future<Socket?> get client => _clientSubject.first;

  @override
  void _init({
    required String appName,
    List<protos.LogLevel>? logLevels,
    List<protos.LogTag>? logTags,
  }) {
    if (isInitialized) {
      throw Exception('FlutterSocketLogPlugin: plugin already initialized');
    }
    isInitialized = true;

    this.appName = appName;
    allLogTags = logTags ?? DefaultLogs.defaultLogTags;
    allLogLevels = logLevels ?? DefaultLogs.defaultLogLevels;
    initSocket();
  }

  void initSocket() async {
    print('Server started listening...');
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 4567);

    _server?.listen((mClient) {
      handleConnection(mClient);
    });
  }

  @override
  void _restart() {
    print('restarting...');
    _server?.close();
    Future.delayed(const Duration(seconds: 2));
    initSocket();
  }

  @override
  Future<String?> get _wifiIp => NetworkInfo().getWifiIP();

  void handleConnection(Socket mClient) {
    print('New Client: ${mClient.address}');
    mClient.listen(
      (Uint8List data) async {
        print('Got message: ${String.fromCharCodes(data)}');
        final message = String.fromCharCodes(data);
        if (message == 'flutter_socket_log_plugin') {
          print('closing last client');
          await closeLastClient();
          print('New client connected. Address: ${mClient.address}');
          _clientSubject.add(mClient);
        } else {
          print('Unknown client: address: ${mClient.address}, message: $message');
          mClient.close();
        }
      },
      onError: (error) async {
        await closeClient(mClient);
      },
      onDone: () async {
        await closeClient(mClient);
      },
    );
  }

  Future<void> closeLastClient() async => (await _clientSubject.first)?.close();

  Future<void> closeClient(Socket mClient) async {
    Socket? lastClient = await _clientSubject.last;
    if (lastClient != null && lastClient.address == mClient.address) {
      _clientSubject.add(null);
    }
    mClient.close();
  }

  @override
  void _log(
    String log,
    protos.LogLevel logLevel,
    List<protos.LogTag> logTags,
  ) {
    protos.LogMessage message = ProtoMaker.createLogMessage(
      appName: appName,
      message: log,
      logLevel: logLevel,
      logTags: logTags,
      allLogTags: allLogTags,
      allLogLevels: allLogLevels,
    );

    client.then((Socket? mClient) {
      if (mClient == null) {
        print('flutter_socket_log_impl: Client is null. NOT LOGGING');
        return;
      }

      mClient.write(message.writeToJson());
    });
  }
}
