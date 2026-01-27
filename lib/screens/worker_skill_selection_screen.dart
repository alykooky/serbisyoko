import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkerSkillSelectionScreen extends StatefulWidget {
  final String userId; // from signup
  const WorkerSkillSelectionScreen({super.key, required this.userId});

  @override
  State<WorkerSkillSelectionScreen> createState() =>
      _WorkerSkillSelectionScreenState();
}

class _WorkerSkillSelectionScreenState
    extends State<WorkerSkillSelectionScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> allSkills = [];
  final Map<String, String> selectedSkills = {}; // skill_id -> experience level
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    try {
      final data = await supabase.from('skills').select('id, name, category');
      setState(() {
        allSkills = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      debugPrint('Error loading skills: $e');
      setState(() => loading = false);
    }
  }

  Future<void> _saveSkills() async {
    if (selectedSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one skill.')),
      );
      return;
    }

    setState(() => saving = true);
    final inserts = selectedSkills.entries.map((entry) => {
          'worker_id': widget.userId,
          'skill_id': entry.key,
          'experience_level': entry.value,
        });

    try {
      await supabase.from('worker_skills').insert(inserts.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skills saved successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error saving skills: $e');
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
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('Select Your Skills'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...allSkills.map((skill) {
            final id = skill['id'].toString();
            final name = skill['name'];
            final isSelected = selectedSkills.containsKey(id);

            return Card(
              elevation: 2,
              child: ExpansionTile(
                title: Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            selectedSkills[id] = 'Intermediate'; // default
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
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Experience: ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              DropdownButton<String>(
                                value: selectedSkills[id],
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Beginner',
                                      child: Text('Beginner')),
                                  DropdownMenuItem(
                                      value: 'Intermediate',
                                      child: Text('Intermediate')),
                                  DropdownMenuItem(
                                      value: 'Expert', child: Text('Expert')),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedSkills[id] =
                                        value ?? 'Intermediate';
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ]
                    : [],
              ),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: saving ? null : _saveSkills,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.save),
            label: Text(saving ? 'Saving...' : 'Save My Skills'),
          ),
        ],
      ),
    );
  }
}
