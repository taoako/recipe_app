import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:final_proj/views/edit_recipe_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';
import '../services/app_logger.dart';
import '../services/security_service.dart';
import '../model/recipe.dart';
import 'edit_profile_page.dart';
import '../model/user.dart';
import 'follow_list_page.dart';
import 'recipe_detail_page.dart';
import 'report_problem_page.dart';
import '../services/like_services.dart';
import '../services/input_validator.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 0;

  Future<void> _openEditProfile() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .get();

    if (!doc.exists) return;

    final data = doc.data() ?? <String, dynamic>{};
    data['uid'] = data['uid'] ?? firebaseUser.uid;
    final appUser = AppUser.fromJson(Map<String, dynamic>.from(data));

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(user: appUser)),
    );
  }

  /// Show a dialog to enable / disable Two-Factor Authentication.
  /// Enabling triggers the authenticator app setup flow (QR code).
  /// Disabling removes the TOTP secret.
  Future<void> _showTwoFactorToggle() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .get();

    if (!userDoc.exists || !mounted) return;

    final data = userDoc.data() ?? {};
    final twoFAEnabled = data['twoFactorEnabled'] == true;

    if (twoFAEnabled) {
      // ── Currently enabled → ask to disable ───────────────────────────────
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.deepOrange),
              SizedBox(width: 10),
              Text(
                'Disable 2FA?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Disabling 2FA will remove the authenticator app '
                        'link. Your account will be less secure.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep enabled'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Disable'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await SecurityService.disableTOTP(firebaseUser.uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Two-Factor Authentication disabled.'),
              backgroundColor: Colors.grey,
            ),
          );
        }
      }
    } else {
      // ── Currently disabled → launch setup flow ────────────────────────────
      if (!mounted) return;
      final setupOk = await SecurityService.show2FADialog(
        context,
        firebaseUser.uid,
        firebaseUser.email ?? '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              setupOk
                  ? 'Two-Factor Authentication enabled!'
                  : '2FA setup cancelled.',
            ),
            backgroundColor: setupOk ? Colors.green : Colors.grey,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        elevation: 4,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFFFA726),
                Color(0xFFFF7043),
              ], // soft orange gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          "My Profile",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            color: Colors.white,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'edit_profile') {
                _openEditProfile();
              } else if (value == 'two_factor') {
                _showTwoFactorToggle();
              } else if (value == 'logout') {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                // Log logout BEFORE signing out (need auth to write)
                await AppLogger.logInfo(
                  LogEvent.logout,
                  'User logged out',
                  userId: uid,
                );
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed("/login");
                }
              } else if (value == 'report') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportProblemPage()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_profile',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Edit Profile',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'two_factor',
                child: Row(
                  children: [
                    Icon(
                      Icons.security_outlined,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Two-Factor Auth',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(
                      Icons.bug_report_outlined,
                      color: Colors.orange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Report a Problem',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Log Out', style: TextStyle(color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🖼 Header with blurred background
            Stack(
              children: [
                Container(
                  height: 290,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/backgroundpic.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(color: Colors.black.withOpacity(0.4)),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Profile Picture with Edit Button
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 52,
                              backgroundImage:
                                  (user != null &&
                                      user.photoURL != null &&
                                      user.photoURL!.isNotEmpty)
                                  ? NetworkImage(user.photoURL!)
                                  : null,
                              child:
                                  (user == null ||
                                      user.photoURL == null ||
                                      user.photoURL!.isEmpty)
                                  ? const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            right: MediaQuery.of(context).size.width / 2 - 70,
                            bottom: 4,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // User name
                      Text(
                        user?.displayName ?? "Unknown User",
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 15),

                      // Stats row
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return _buildStats(0, 0, 0);
                          }
                          final data = snapshot.data!.data() ?? {};
                          final followers =
                              (data['followers'] as List<dynamic>? ?? [])
                                  .length;
                          final following =
                              (data['following'] as List<dynamic>? ?? [])
                                  .length;
                          return StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('recipes')
                                .where('authorId', isEqualTo: user?.uid)
                                .snapshots(),
                            builder: (context, snap) {
                              int recipes = 0;
                              if (snap.hasData) {
                                recipes = snap.data!.docs.where((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final archived =
                                      data['isArchived'] == true ||
                                      data['isArchived'] == 'true';
                                  return !archived; // exclude archived from public count
                                }).length;
                              }
                              return _buildStats(recipes, following, followers);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ✨ Smooth rounded transition
            Container(
              height: 25,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    offset: Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),

            // 📑 Tabs + Content
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _tabButton("Recipes", 0),
                      const SizedBox(width: 25),
                      _tabButton("Liked", 1),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _selectedIndex == 0 ? _buildFoodGrid() : _buildLikedGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(int recipes, int following, int followers) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem("Recipes", recipes),

          GestureDetector(
            onTap: () {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowListPage(userId: currentUser.uid),
                ),
              );
            },
            child: _statItem("Following", following),
          ),

          GestureDetector(
            onTap: () {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowListPage(userId: currentUser.uid),
                ),
              );
            },
            child: _statItem("Followers", followers),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white, // ✅ Make the numbers white
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey, // label stays grey for contrast
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _tabButton(String text, int index) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black : Colors.grey,
            ),
          ),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              height: 2,
              width: 40,
              color: Colors.orange,
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final user = FirebaseAuth.instance.currentUser;
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null || user == null) return;

    final bytes = await image.readAsBytes();
    final imageError = InputValidator.validateImageUpload(
      fileName: image.name,
      fileSizeBytes: bytes.length,
      fileBytes: bytes,
    );
    if (imageError != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(imageError)));
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final cloudinary = CloudinaryService();
      final uploadedUrl = await cloudinary.uploadFile(
        File(image.path),
        folder: 'profile_images',
      );
      await user.updatePhotoURL(uploadedUrl);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'profileImageUrl': uploadedUrl},
      );
      unawaited(
        AppLogger.logInfo(
          LogEvent.imageUpload,
          'Profile image updated',
          userId: user.uid,
        ),
      );
    } catch (e) {
      unawaited(
        AppLogger.logError(
          LogEvent.imageUpload,
          'Profile image upload failed: ${e.toString().split('\n').first}',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile image. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) Navigator.pop(context);
      setState(() {});
    }
  }

  // Recipes Tab
  Widget _buildFoodGrid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Not signed in.'));
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('recipes')
          .where('authorId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs =
            snapshot.data!.docs; // show all (including archived) to owner
        if (docs.isEmpty) {
          return const Center(child: Text("No recipes yet"));
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 20,
            childAspectRatio: 1.10,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final recipe = Recipe.fromJson(data);
            return _ProfileRecipeCard(
              recipe: recipe,
              recipeId: docs[index].id,
              isOwner: true,
            );
          },
        );
      },
    );
  }

  // Liked Tab
  Widget _buildLikedGrid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Not signed in.'));
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('recipes')
          .where('likedBy', arrayContains: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final archived =
              data['isArchived'] == true || data['isArchived'] == 'true';
          final authorId = data['authorId']?.toString() ?? '';
          // hide archived liked recipes unless current user is the author
          if (archived && authorId != user.uid) return false;
          return true;
        }).toList();
        if (docs.isEmpty) {
          return const Center(child: Text("No liked recipes yet"));
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 20,
            childAspectRatio: 0.90,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final recipe = Recipe.fromJson(data);
            return _ProfileRecipeCard(
              recipe: recipe,
              recipeId: docs[index].id,
              isOwner: false,
            );
          },
        );
      },
    );
  }
}

// Profile Recipe Card
class _ProfileRecipeCard extends StatefulWidget {
  final Recipe recipe;
  final String recipeId;
  final bool isOwner;
  const _ProfileRecipeCard({
    required this.recipe,
    required this.recipeId,
    required this.isOwner,
    Key? key,
  }) : super(key: key);

  @override
  State<_ProfileRecipeCard> createState() => _ProfileRecipeCardState();
}

class _ProfileRecipeCardState extends State<_ProfileRecipeCard> {
  late bool _isLiked;
  late int _likesCount;
  bool _isLoading = false;
  bool _appealSubmitting = false;

  Future<void> _submitAppeal(Recipe recipe) async {
    if (_appealSubmitting) return;
    setState(() => _appealSubmitting = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance
        .collection('recipeAppeals')
        .doc(widget.recipeId); // one appeal per recipe
    try {
      final existing = await docRef.get();
      if (existing.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Appeal already submitted.')),
          );
        }
        return;
      }

      String reason = '';
      reason =
          await showDialog<String>(
            context: context,
            builder: (ctx) {
              final controller = TextEditingController();
              return AlertDialog(
                title: const Text('Appeal Hidden Recipe'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Provide a short reason why this recipe should be reviewed.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Enter your appeal reason...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('SUBMIT'),
                  ),
                ],
              );
            },
          ) ??
          '';

      if (reason.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Appeal cancelled.')));
        }
        return;
      }

      await docRef.set({
        'recipeId': widget.recipeId,
        'authorId': uid,
        'title': recipe.title,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'reason': reason.trim(),
        'isHidden': recipe.isHidden,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Appeal submitted.')));
      }
    } catch (e) {
      AppLogger.error('Failed to submit appeal', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit appeal. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _appealSubmitting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    _isLiked =
        currentUser != null && widget.recipe.likedBy.contains(currentUser.uid);
    _likesCount = widget.recipe.likes;
  }

  Future<void> _handleLike() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final bool originalIsLiked = _isLiked;
    final int originalLikesCount = _likesCount;

    setState(() {
      if (_isLiked)
        _likesCount--;
      else
        _likesCount++;
      _isLiked = !_isLiked;
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      await LikeService().toggleLike(
        widget.recipe.id,
        currentUser.uid,
        currentUser.displayName ?? "Unknown",
        currentUser.photoURL ?? "",
      );
    } catch (e) {
      AppLogger.error('Failed to update like', e);
      setState(() {
        _isLiked = originalIsLiked;
        _likesCount = originalLikesCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update like. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;

    // Archived posts are fully disabled; hidden posts remain actionable
    final bool isArchived = recipe.isArchived == true;
    final bool isHidden = recipe.isHidden == true;
    final bool isDisabled = isArchived; // only archived fully disabled

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author Row ONLY for Liked tab
        if (!widget.isOwner)
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(recipe.authorId)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox(height: 30);
              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              if (userData == null) return const SizedBox(height: 30);

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage:
                          (userData['profileImageUrl'] != null &&
                              userData['profileImageUrl'].isNotEmpty)
                          ? NetworkImage(userData['profileImageUrl'])
                          : null,
                      child:
                          (userData['profileImageUrl'] == null ||
                              userData['profileImageUrl'].isEmpty)
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        userData['username'] ?? "Unknown",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

        // Recipe Card
        Expanded(
          child: GestureDetector(
            onTap: isDisabled
                ? null // disable tap if archived or hidden
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailPage(recipe: recipe),
                      ),
                    );
                  },
            child: Stack(
              children: [
                // Recipe Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: recipe.coverImageUrl.isNotEmpty
                      ? Image.network(
                          recipe.coverImageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(child: Icon(Icons.image)),
                        ),
                ),

                // 🔒 or 🙈 Overlay for archived or hidden recipes
                if (isArchived || isHidden)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isArchived
                                  ? Colors.red.withOpacity(0.8)
                                  : Colors.orange.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isArchived
                                      ? Icons.lock
                                      : Icons.visibility_off,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isArchived ? 'Archived' : 'Hidden',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ❤️ Heart icon ONLY for Liked tab (not disabled)
                if (!widget.isOwner && !isDisabled)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: _handleLike,
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        radius: 16,
                        child: _isLoading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isLiked ? Colors.red : Colors.grey,
                                size: 18,
                              ),
                      ),
                    ),
                  ),

                // ⋮ Menu (Edit/Delete) ONLY for Recipes tab (not disabled)
                if (widget.isOwner && !isDisabled)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 20,
                        ),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditRecipePage(
                                  recipeId: widget.recipeId,
                                  recipeData: recipe.toJson(),
                                ),
                              ),
                            );
                          } else if (value == 'delete') {
                            final recipeTitle = recipe.title;
                            await FirebaseFirestore.instance
                                .collection('recipes')
                                .doc(widget.recipeId)
                                .delete();
                            unawaited(
                              AppLogger.logInfo(
                                LogEvent.recipeAction,
                                'Recipe deleted: $recipeTitle',
                                metadata: {
                                  'action': 'delete',
                                  'recipeId': widget.recipeId,
                                },
                              ),
                            );
                          } else if (value == 'appeal') {
                            await _submitAppeal(recipe);
                          }
                        },
                        itemBuilder: (context) {
                          return [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                            if (isHidden)
                              PopupMenuItem(
                                value: 'appeal',
                                enabled: !_appealSubmitting,
                                child: Row(
                                  children: [
                                    if (_appealSubmitting)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    if (_appealSubmitting)
                                      const SizedBox(width: 8),
                                    Text(
                                      _appealSubmitting
                                          ? 'Submitting...'
                                          : 'Appeal',
                                    ),
                                  ],
                                ),
                              ),
                          ];
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Title + Meta + Likes
        Text(
          recipe.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${recipe.category} • ${recipe.cookingDuration} mins',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.favorite, color: Colors.red.shade400, size: 14),
            const SizedBox(width: 4),
            Text('$_likesCount likes', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
