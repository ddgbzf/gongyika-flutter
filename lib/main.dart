import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  runApp(const GongyikaApp());
}

class GongyikaApp extends StatelessWidget {
  const GongyikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '工艺卡',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ServerSelectPage(),
    );
  }
}

// 服务器配置
class ServerConfig {
  final String name;
  final String host;
  final int port;
  final String user;
  final String password;
  final String baseDir;
  final String id;

  const ServerConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.baseDir,
    required this.id,
  });
}

const servers = [
  ServerConfig(
    name: '冲压工艺卡',
    host: '192.168.2.56',
    port: 21,
    user: 'gongyi',
    password: '12345678',
    baseDir: '/工艺卡/冲压工艺/',
    id: '1',
  ),
  ServerConfig(
    name: '焊接工艺卡',
    host: '192.168.2.56',
    port: 21,
    user: 'gongyi',
    password: '12345678',
    baseDir: '/工艺卡/焊接工艺卡/',
    id: '2',
  ),
  ServerConfig(
    name: '冠立冲压工艺卡',
    host: '192.168.1.50',
    port: 21,
    user: 'anonymous',
    password: '',
    baseDir: '/资料汇总/资料汇总/冠立工艺资料/冲压工艺卡/',
    id: '3',
  ),
  ServerConfig(
    name: '冠立焊接工艺卡',
    host: '192.168.1.50',
    port: 21,
    user: 'anonymous',
    password: '',
    baseDir: '/资料汇总/资料汇总/冠立工艺资料/焊接工艺卡/',
    id: '4',
  ),
];

// 服务器选择页面
class ServerSelectPage extends StatelessWidget {
  const ServerSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('工艺卡')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '请选择服务器',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ...servers.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FileListPage(server: s),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(s.name, style: const TextStyle(fontSize: 16)),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// 文件列表页面
class FileListPage extends StatefulWidget {
  final ServerConfig server;
  const FileListPage({super.key, required this.server});

  @override
  State<FileListPage> createState() => _FileListPageState();
}

class _FileListPageState extends State<FileListPage> {
  final _searchController = TextEditingController();
  List<String> _fileCache = [];
  List<String> _searchResults = [];
  bool _isLoading = false;
  String _status = '';
  double? _progress;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_${widget.server.id}';
    final cacheStr = prefs.getString(cacheKey);
    if (cacheStr != null) {
      setState(() {
        _fileCache = List<String>.from(jsonDecode(cacheStr));
        _status = '已加载 ${_fileCache.length} 个文件';
      });
    } else {
      setState(() => _status = '无缓存，请先同步');
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_${widget.server.id}';
    await prefs.setString(cacheKey, jsonEncode(_fileCache));
  }

  Future<FTPConnect> _connectFTP() async {
    final ftp = FTPConnect(
      widget.server.host,
      user: widget.server.user,
      pass: widget.server.password,
      port: widget.server.port,
      securityType: SecurityType.none,
      timeout: 10,
    );
    await ftp.connect();
    await ftp.changeDirectory(widget.server.baseDir);
    return ftp;
  }

  Future<void> _syncCache() async {
    setState(() {
      _isLoading = true;
      _status = '正在同步缓存...';
      _progress = 0;
    });

    try {
      final ftp = await _connectFTP();
      final oldCache = Set<String>.from(_fileCache);
      final newFiles = <String>[];

      await _scanDirectory(ftp, widget.server.baseDir, newFiles, (progress) {
        setState(() {
          _status = '已扫描 ${newFiles.length} 个文件...';
        });
      });

      // 合并
      for (final f in newFiles) {
        if (!oldCache.contains(f)) {
          _fileCache.add(f);
        }
      }

      await _saveCache();
      ftp.disconnect();

      setState(() {
        _isLoading = false;
        _status = '同步完成，共 ${_fileCache.length} 个文件';
        _progress = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '同步失败: $e';
        _progress = null;
      });
    }
  }

  Future<void> _scanDirectory(
    FTPConnect ftp,
    String path,
    List<String> files,
    Function(int) onProgress,
  ) async {
    try {
      await ftp.changeDirectory(path);
      final items = await ftp.listDirectoryContent();

      for (final item in items) {
        if (item.name == '.' || item.name == '..') continue;
        if (item.name.startsWith('~\$')) continue;
        if (item.name.toLowerCase().endsWith('.bak') ||
            item.name.toLowerCase().endsWith('.dwl') ||
            item.name.toLowerCase().endsWith('.dwl2')) {
          continue;
        }

        final fullPath = '$path${item.name}';
        if (item.isDirectory) {
          await _scanDirectory(ftp, '$fullPath/', files, onProgress);
        } else {
          files.add(fullPath);
        }
      }
    } catch (e) {
      // 跳过无法访问的目录
    }
  }

  void _search() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    final tokens = _parseKeywords(keyword);
    final results = <String>[];

    for (final path in _fileCache) {
      if (_allMatch(path, tokens)) {
        results.add(path);
      }
    }

    setState(() => _searchResults = results);
  }

  List<String> _parseKeywords(String text) {
    final tokens = <String>[];
    final regex = RegExp(r'[A-Za-z0-9]+|[\u4e00-\u9fa5]+');
    for (final match in regex.allMatches(text)) {
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  bool _allMatch(String path, List<String> tokens) {
    final upper = path.toUpperCase();
    for (final t in tokens) {
      if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(t)) {
        if (!upper.contains(t.toUpperCase())) return false;
      } else {
        if (!path.contains(t)) return false;
      }
    }
    return true;
  }

  Future<void> _downloadAndOpen(String remotePath) async {
    setState(() {
      _isLoading = true;
      _status = '正在下载...';
    });

    try {
      final ftp = await _connectFTP();
      final fileName = remotePath.split('/').last;
      final safeName = fileName.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');

      final dir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${dir.path}/工艺卡');
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final localPath = '${localDir.path}/$safeName';
      final localFile = File(localPath);

      // 检查是否需要更新
      if (await localFile.exists()) {
        final localMod = await localFile.lastModified();
        try {
          final remoteMod = await ftp.lastModified(remotePath);
          if (localMod.isAfter(remoteMod) || localMod.isAtSameMomentAs(remoteMod)) {
            ftp.disconnect();
            setState(() {
              _isLoading = false;
              _status = '已是最新，正在打开...';
            });
            await OpenFile.open(localPath);
            return;
          }
        } catch (_) {}
      }

      // 下载
      final data = await ftp.getData(remotePath);
      await localFile.writeAsBytes(data);
      ftp.disconnect();

      setState(() {
        _isLoading = false;
        _status = '下载完成，正在打开...';
      });
      await OpenFile.open(localPath);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '下载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _isLoading ? null : _syncCache,
            tooltip: '同步缓存',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: '输入关键词搜索',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _search,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          if (_progress != null)
            LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_status, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('输入关键词搜索文件'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final path = _searchResults[index];
                      final relPath = path.replaceFirst(widget.server.baseDir, '');
                      final parts = relPath.split('/');
                      final display = parts.length >= 2
                          ? parts.sublist(parts.length - 2).join('/')
                          : relPath;

                      return ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(display, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(relPath,
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        onTap: () => _downloadAndOpen(path),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
