import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageSkillsScreen extends StatefulWidget {
  final String workerId;
  const ManageSkillsScreen({super.key, required this.workerId});

  @override
  State<ManageSkillsScreen> createState() => _ManageSkillsScreenState();
}

class _ManageSkillsScreenState extends State<ManageSkillsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> allSkills = [];
  final Map<String, String> selectedSkills = {};
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    try {
      final skills = await supabase.from('services').select('id, name');

      // Try service_id first, fallback to skill_id if needed
      List<dynamic> current = [];
      try {
        current = await supabase
            .from('worker_skills')
            .select('service_id, level')
            .eq('worker_id', widget.workerId);
      } catch (e) {
        // Fallback to skill_id if service_id doesn't exist
        try {
          current = await supabase
              .from('worker_skills')
              .select('skill_id, experience_level')
              .eq('worker_id', widget.workerId);
        } catch (e2) {
          debugPrint('Error loading current skills: $e2');
        }
      }

      final selected = <String, String>{};
      for (var s in current) {
        final serviceId = (s['service_id'] ?? s['skill_id'])?.toString();
        if (serviceId != null) {
          // Map level (1-5) to experience level string, or use experience_level if available
          final level = s['level'] as int?;
          final expLevel = s['experience_level']?.toString();
          String experience = 'Intermediate';
          if (expLevel != null) {
            experience = expLevel;
          } else if (level != null) {
            if (level <= 2) {
              experience = 'Beginner';
            } else if (level <= 3) {
              experience = 'Intermediate';
            } else {
              experience = 'Expert';
            }
          }
          selected[serviceId] = experience;
        }
      }

      setState(() {
        allSkills = List<Map<String, dynamic>>.from(skills);
        selectedSkills.addAll(selected);
        loading = false;
      });
    } catch (e) {
      debugPrint('Error loading skills: $e');
      setState(() => loading = false);
    }
  }

  Future<void> _saveSkills() async {
    setState(() => saving = true);
    try {
      await supabase
          .from('worker_skills')
          .delete()
          .eq('worker_id', widget.workerId);
      // Try service_id first, fallback to skill_id if needed
      final entries = selectedSkills.entries.map((e) {
        // Map experience level to numeric level (1-5)
        int level = 3; // Default to intermediate
        switch (e.value) {
          case 'Beginner':
            level = 2;
            break;
          case 'Intermediate':
            level = 3;
            break;
          case 'Expert':
            level = 5;
            break;
        }
        
        // Try service_id schema first
        return {
          'worker_id': widget.workerId,
          'service_id': e.key,
          'level': level,
        };
      }).toList();
      
      try {
        await supabase.from('worker_skills').insert(entries);
      } catch (e) {
        // Fallback to skill_id schema if service_id doesn't work
        final fallbackEntries = <Map<String, dynamic>>[];
        for (final entry in selectedSkills.entries) {
          fallbackEntries.add({
            'worker_id': widget.workerId,
            'skill_id': entry.key,
            'experience_level': entry.value,
          });
        }
        await supabase.from('worker_skills').insert(fallbackEntries);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skills updated successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating skills: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: Color(0xFFED9121))));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFED9121),
        title: const Text('Manage My Skills'),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...allSkills.map((skill) {
            final id = skill['id'].toString();
            final name = skill['name'];
            final isSelected = selectedSkills.containsKey(id);

            return Card(
              child: ExpansionTile(
                title: Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            selectedSkills[id] = 'Intermediate';
                          } else {
                            selectedSkills.remove(id);
                          }
                        });
                      },
                    ),
                    Expanded(child: Text(name)),
                  ],
                ),
                children: isSelected
                    ? [
                        DropdownButton<String>(
                          value: selectedSkills[id],
                          items: const [
                            DropdownMenuItem(
                                value: 'Beginner', child: Text('Beginner')),
                            DropdownMenuItem(
                                value: 'Intermediate',
                                child: Text('Intermediate')),
                            DropdownMenuItem(
                                value: 'Expert', child: Text('Expert')),
                          ],
                          onChanged: (v) {
                            setState(
                                () => selectedSkills[id] = v ?? 'Intermediate');
                          },
                        ),
                        const SizedBox(height: 12),
                      ]
                    : [],
              ),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: saving ? null : _saveSkills,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFED9121),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.save),
            label: Text(saving ? 'Saving...' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}
