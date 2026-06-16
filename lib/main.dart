import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MtaPanelApp());
}

const String kPanelUrl = 'https://panel.qniks.me';
const String kApiKey = 'ptlc_reNyRwR2G2y5xuRyrYRk4lLNqGwlj52JfxZJW1Paz2q';
const String kServerId = '54589635';
const String kMtaHost = 'g1.qniks.me';
const int kMtaHttpPort = 22005;

class MtaPanelApp extends StatelessWidget {
  const MtaPanelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MTA Panel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF3ECFCF),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _resources = [];
  bool _loading = true;
  Timer? _timer;
  final List<String> _logs = [];
  final _cmdController = TextEditingController();

  Map<String, String> get _pteroHeaders => {
    'Authorization': 'Bearer $kApiKey',
    'Content-Type': 'application/json',
    'Accept': 'Application/vnd.pterodactyl.v1+json',
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _loadAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cmdController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStatus(), _loadPlayers(), _loadResources()]);
  }

  Future<void> _loadStatus() async {
    try {
      final res = await http.get(
        Uri.parse('$kPanelUrl/api/client/servers/$kServerId/resources'),
        headers: _pteroHeaders,
      ).timeout(const Duration(seconds: 8));
      if (mounted) setState(() { _status = jsonDecode(res.body); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPlayers() async {
    try {
      final res = await http.get(
        Uri.parse('http://$kMtaHost:$kMtaHttpPort/mta_panel/players'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _players = List<Map<String, dynamic>>.from(data['players'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadResources() async {
    try {
      final res = await http.get(
        Uri.parse('http://$kMtaHost:$kMtaHttpPort/mta_panel/resources'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _resources = List<Map<String, dynamic>>.from(data['resources'] ?? []));
      }
    } catch (_) {}
  }

  bool get _isOnline => _status['attributes']?['current_state'] == 'running';
  double get _cpu => (_status['attributes']?['resources']?['cpu_absolute'] as num?)?.toDouble() ?? 0;
  double get _ram => ((_status['attributes']?['resources']?['memory_bytes'] as num?)?.toDouble() ?? 0) / 1024 / 1024;

  Future<void> _power(String action) async {
    final names = {'start': 'Запустити', 'stop': 'Зупинити', 'restart': 'Рестартити', 'kill': 'Kill'};
    final colors = {'start': Colors.green, 'stop': Colors.orange, 'restart': Colors.blue, 'kill': Colors.red};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        title: Text('${names[action]} сервер?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors[action]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(names[action]!),
          ),
        ],
      ),
    );
    if (ok == true) {
      await http.post(
        Uri.parse('$kPanelUrl/api/client/servers/$kServerId/power'),
        headers: _pteroHeaders,
        body: jsonEncode({'signal': action}),
      );
      _loadStatus();
    }
  }

  Future<void> _sendCmd() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    setState(() { _logs.add('> $cmd'); _cmdController.clear(); });
    try {
      final res = await http.post(
        Uri.parse('$kPanelUrl/api/client/servers/$kServerId/command'),
        headers: _pteroHeaders,
        body: jsonEncode({'command': cmd}),
      );
      setState(() => _logs.add(res.statusCode == 204 ? '[OK] Відправлено' : '[ERR] Помилка'));
    } catch (_) {
      setState(() => _logs.add('[ERR] Немає з\'єднання'));
    }
  }

  Future<void> _kickPlayer(String name) async {
    try {
      await http.post(
        Uri.parse('http://$kMtaHost:$kMtaHttpPort/mta_panel/kick'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'reason': 'Kicked by admin'}),
      );
      _loadPlayers();
    } catch (_) {}
  }

  Future<void> _banPlayer(String name) async {
    try {
      await http.post(
        Uri.parse('http://$kMtaHost:$kMtaHttpPort/mta_panel/ban'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'reason': 'Banned by admin'}),
      );
      _loadPlayers();
    } catch (_) {}
  }

  Future<void> _toggleResource(String name, bool isRunning) async {
    try {
      await http.post(
        Uri.parse('http://$kMtaHost:$kMtaHttpPort/mta_panel/resource'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'action': isRunning ? 'stop' : 'start'}),
      );
      _loadResources();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        Expanded(child: IndexedStack(index: _selectedIndex, children: [
          _buildDashboard(),
          _buildPlayers(),
          _buildResources(),
          _buildConsole(),
        ])),
        _buildNav(),
      ])),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(color: Color(0xFF131625), border: Border(bottom: BorderSide(color: Color(0xFF252840)))),
    child: Row(children: [
      Container(width: 34, height: 34,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)]), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.sports_esports, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MTA Panel', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text('g1.qniks.me:30319', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (_isOnline ? Colors.green : Colors.red).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isOnline ? Colors.green : Colors.red),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: _isOnline ? Colors.green : Colors.red)),
          const SizedBox(width: 5),
          Text(_isOnline ? 'Online' : 'Offline', style: TextStyle(color: _isOnline ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
      IconButton(icon: const Icon(Icons.refresh, color: Colors.white70, size: 20), onPressed: _loadAll),
    ]),
  );

  Widget _buildDashboard() => RefreshIndicator(
    onRefresh: _loadAll,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Статистика', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statCard(Icons.speed, 'CPU', '${_cpu.toStringAsFixed(1)}%', const Color(0xFFFF6B6B))),
          const SizedBox(width: 12),
          Expanded(child: _statCard(Icons.memory, 'RAM', '${_ram.toStringAsFixed(0)} MB', const Color(0xFF3ECFCF))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statCard(Icons.people, 'Гравці', '${_players.length}', const Color(0xFF6C63FF))),
          const SizedBox(width: 12),
          Expanded(child: _statCard(Icons.extension, 'Ресурси', '${_resources.where((r) => r['running'] == true).length}/${_resources.length}', Colors.orange)),
        ]),
        const SizedBox(height: 24),
        const Text('Керування', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.5,
          children: [
            _powerBtn('start', Icons.play_arrow, 'Старт', Colors.green),
            _powerBtn('restart', Icons.refresh, 'Рестарт', Colors.blue),
            _powerBtn('stop', Icons.stop, 'Стоп', Colors.orange),
            _powerBtn('kill', Icons.dangerous, 'Kill', Colors.red),
          ],
        ),
      ]),
    ),
  );

  Widget _statCard(IconData icon, String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFF131625), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.3))),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ])),
    ]),
  );

  Widget _powerBtn(String action, IconData icon, String label, Color color) => ElevatedButton.icon(
    style: ElevatedButton.styleFrom(backgroundColor: color.withOpacity(0.15), foregroundColor: color, side: BorderSide(color: color.withOpacity(0.4)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    onPressed: () => _power(action),
  );

  Widget _buildPlayers() {
    if (_players.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.people_outline, size: 60, color: Colors.grey[700]),
      const SizedBox(height: 12),
      Text('Гравців немає онлайн', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _players.length,
      itemBuilder: (_, i) {
        final p = _players[i];
        final name = p['name'] ?? 'Unknown';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF131625), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF252840))),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)]), borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text('Ping: ${p['ping'] ?? 0}ms', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ])),
            IconButton(icon: const Icon(Icons.logout, color: Colors.orange, size: 20), onPressed: () => _confirmAction(context, 'Кікнути', name, false)),
            IconButton(icon: const Icon(Icons.block, color: Colors.red, size: 20), onPressed: () => _confirmAction(context, 'Забанити', name, true)),
          ]),
        );
      },
    );
  }

  void _confirmAction(BuildContext context, String action, String name, bool isBan) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D2E),
      title: Text('$action $name?', style: const TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isBan ? Colors.red : Colors.orange),
          onPressed: () { Navigator.pop(ctx); isBan ? _banPlayer(name) : _kickPlayer(name); },
          child: Text(action),
        ),
      ],
    ));
  }

  Widget _buildResources() {
    if (_resources.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.extension_off, size: 60, color: Colors.grey[700]),
      const SizedBox(height: 12),
      Text('Ресурси не знайдено', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
      Text('Перевір Lua скрипт на сервері', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _resources.length,
      itemBuilder: (_, i) {
        final r = _resources[i];
        final name = r['name'] ?? '';
        final running = r['running'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF131625), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF252840))),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: running ? Colors.green : Colors.grey)),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
            Text(running ? 'Running' : 'Stopped', style: TextStyle(color: running ? Colors.green : Colors.grey, fontSize: 12)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleResource(name, running),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (running ? Colors.orange : Colors.green).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: running ? Colors.orange : Colors.green),
                ),
                child: Text(running ? 'Стоп' : 'Старт', style: TextStyle(color: running ? Colors.orange : Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildConsole() => Column(children: [
    Expanded(child: Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0A0C14), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF252840))),
      child: _logs.isEmpty
        ? Center(child: Text('Введіть команду нижче', style: TextStyle(color: Colors.grey[600])))
        : ListView.builder(itemCount: _logs.length, itemBuilder: (_, i) {
            final l = _logs[i];
            Color c = Colors.grey[400]!;
            if (l.startsWith('>')) c = const Color(0xFF6C63FF);
            if (l.startsWith('[OK]')) c = Colors.green;
            if (l.startsWith('[ERR]')) c = Colors.red;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: TextStyle(color: c, fontSize: 12, fontFamily: 'monospace')));
          }),
    )),
    Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Row(children: [
      Expanded(child: TextField(
        controller: _cmdController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Введіть команду...', hintStyle: TextStyle(color: Colors.grey[600]),
          filled: true, fillColor: const Color(0xFF131625),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF252840))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF252840))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onSubmitted: (_) => _sendCmd(),
      )),
      const SizedBox(width: 10),
      Container(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)]), borderRadius: BorderRadius.circular(12)),
        child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendCmd),
      ),
    ])),
  ]);

  Widget _buildNav() => BottomNavigationBar(
    currentIndex: _selectedIndex,
    onTap: (i) => setState(() => _selectedIndex = i),
    backgroundColor: const Color(0xFF131625),
    selectedItemColor: const Color(0xFF6C63FF),
    unselectedItemColor: Colors.grey[600],
    type: BottomNavigationBarType.fixed,
    elevation: 0,
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Панель'),
      BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Гравці'),
      BottomNavigationBarItem(icon: Icon(Icons.extension), label: 'Ресурси'),
      BottomNavigationBarItem(icon: Icon(Icons.terminal), label: 'Консоль'),
    ],
  );
}
