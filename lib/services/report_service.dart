import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_logger.dart';

/// Supported reasons a user can select when reporting a post.
class ReportReason {
  static const inappropriate = 'inappropriate';
  static const spam = 'spam';
  static const misinformation = 'misinformation';
  static const violence = 'violence';
  static const other = 'other';

  static const all = [inappropriate, spam, misinformation, violence, other];

  static String label(String reason) => switch (reason) {
    inappropriate => 'Inappropriate Content',
    spam => 'Spam',
    misinformation => 'Misinformation',
    violence => 'Violence / Harmful',
    _ => 'Other',
  };
}

/// Service for submitting and managing post reports.
class ReportService {
  static final _db = FirebaseFirestore.instance;

  /// Submit a report for a recipe post.
  /// Returns `true` on success, throws on error.
  static Future<bool> reportPost({
    required String postId,
    required String postTitle,
    required String postCoverImage,
    required String postAuthorId,
    required String postAuthorName,
    required String reason,
    String description = '',
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    // Use a deterministic document ID to prevent duplicate reports from the
    // same user for the same post — no composite index needed.
    final docId = '${currentUser.uid}_$postId';
    final docRef = _db.collection('postReports').doc(docId);

    final existing = await docRef.get();
    if (existing.exists) {
      throw Exception('already_reported');
    }

    await docRef.set({
      'postId': postId,
      'postTitle': postTitle,
      'postCoverImage': postCoverImage,
      'postAuthorId': postAuthorId,
      'postAuthorName': postAuthorName,
      'reporterId': currentUser.uid,
      'reporterName': currentUser.displayName ?? 'Unknown',
      'reason': reason,
      'description': description,
      'status': 'pending', // pending | reviewed_valid | reviewed_dismissed
      'createdAt': FieldValue.serverTimestamp(),
    });

    AppLogger.logInfo(
      LogEvent.userAction,
      'User reported post: $postTitle',
      userId: currentUser.uid,
      metadata: {'postId': postId, 'reason': reason},
    );

    return true;
  }

  /// Moderator action: hide the reported post and mark report as valid.
  static Future<void> resolveReport({
    required String reportId,
    required String postId,
    required bool hidePost,
    String? note,
  }) async {
    final moderator = FirebaseAuth.instance.currentUser;
    final batch = _db.batch();

    if (hidePost) {
      batch.update(_db.collection('recipes').doc(postId), {'isHidden': true});
    }

    batch.update(_db.collection('postReports').doc(reportId), {
      'status': hidePost ? 'reviewed_valid' : 'reviewed_dismissed',
      'reviewedBy': moderator?.uid ?? '',
      'reviewedByName': moderator?.displayName ?? 'Moderator',
      'reviewNote': note ?? '',
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    AppLogger.logInfo(
      LogEvent.adminAction,
      hidePost ? 'Moderator hid post via report' : 'Moderator dismissed report',
      userId: moderator?.uid,
      metadata: {'reportId': reportId, 'postId': postId},
    );
  }
}
