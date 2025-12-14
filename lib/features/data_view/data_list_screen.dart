import 'package:flutter/material.dart';
import '../../models/session.dart';
import '../../services/session_storage.dart';
import '../../services/session_exporter.dart';

class DataListScreen extends StatefulWidget {
  const DataListScreen({super.key});

  @override
  State<DataListScreen> createState() => _DataListScreenState();
}

class _DataListScreenState extends State<DataListScreen> {
  final SessionStorage _sessionStorage = SessionStorage();
  List<Session>? _sessions;
  bool _loading = true;
  
  // Selection state
  bool _isSelectionMode = false;
  final Set<String> _selectedSessionIds = {};

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _sessionStorage.loadSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessions = [];
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sessions: $e')),
        );
      }
    }
  }

  void _toggleSelection(String sessionId) {
    setState(() {
      if (_selectedSessionIds.contains(sessionId)) {
        _selectedSessionIds.remove(sessionId);
        if (_selectedSessionIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedSessionIds.add(sessionId);
      }
    });
  }

  void _enterSelectionMode(String sessionId) {
    setState(() {
      _isSelectionMode = true;
      _selectedSessionIds.add(sessionId);
    });
  }

  void _shareSelected() async {
    if (_sessions == null || _selectedSessionIds.isEmpty) return;
    
    final selectedSessions = _sessions!
        .where((s) => _selectedSessionIds.contains(s.id))
        .toList();
        
    await SessionExporter().shareSessions(selectedSessions);
    
    setState(() {
      _isSelectionMode = false;
      _selectedSessionIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Data')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final allSessions = _sessions ?? [];
    final depthSessions = allSessions.where((s) => s.enableDepth).toList();
    final rgbSessions = allSessions.where((s) => !s.enableDepth).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSelectionMode 
              ? '${_selectedSessionIds.length} Selected' 
              : 'Saved Data'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'With Depth', icon: Icon(Icons.layers)),
              Tab(text: 'RGB Only', icon: Icon(Icons.camera_alt)),
            ],
          ),
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedSessionIds.clear();
                    });
                  },
                )
              : null,
          actions: [
            if (_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareSelected,
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildSessionList(depthSessions),
            _buildSessionList(rgbSessions),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSession(Session session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text('Delete session "${session.animalId ?? session.id}" and all its files? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _sessionStorage.deleteSession(session.id);
      _loadSessions(); // Reload list
    }
  }

  Widget _buildSessionList(List<Session> sessions) {
    if (sessions.isEmpty) {
      return const Center(child: Text('No sessions found'));
    }
    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isSelected = _selectedSessionIds.contains(session.id);
        
        return ListTile(
          leading: _isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (val) => _toggleSelection(session.id),
                )
              : null,
          title: Text(session.animalId ?? session.id),
          subtitle: Text(
              '${session.frames.length} frames • ${session.createdAt.toString().split('.')[0]}'),
          trailing: !_isSelectionMode 
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () => SessionExporter().shareSession(session),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.grey),
                      onPressed: () => _deleteSession(session),
                    ),
                  ],
                )
              : null,
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(session.id);
            }
          },
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(session.id);
            } else {
              Navigator.pushNamed(
                context,
                '/session_summary',
                arguments: session,
              );
            }
          },
          selected: isSelected,
          selectedTileColor: Colors.blue.withOpacity(0.1),
        );
      },
    );
  }
}
