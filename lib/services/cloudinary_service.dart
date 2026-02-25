import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:http/http.dart' as http;
import 'env_config.dart';
import 'app_logger.dart';

class CloudinaryService {
  late final CloudinaryPublic cloudinary;

  CloudinaryService() {
    cloudinary = CloudinaryPublic(
      EnvConfig.cloudinaryCloudName,
      EnvConfig.cloudinaryUploadPreset,
      cache: false,
    );
  }

  Future<String> uploadFile(File file, {String? folder}) async {
    try {
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Image,
          folder: folder,
        ),
      );
      return response.secureUrl;
    } catch (e) {
      AppLogger.error('Cloudinary file upload failed', e);
      rethrow;
    }
  }

  Future<String> uploadImageBytes(
    Uint8List imageBytes, {
    String folder = '',
  }) async {
    try {
      final cloudName = EnvConfig.cloudinaryCloudName;
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      var request = http.MultipartRequest('POST', uri);

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'upload.jpg',
        ),
      );

      request.fields['upload_preset'] = EnvConfig.cloudinaryUploadPreset;
      if (folder.isNotEmpty) {
        request.fields['folder'] = folder;
      }

      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception(
          'Cloudinary upload returned status ${response.statusCode}',
        );
      }

      final responseData = await response.stream.toBytes();
      final result = String.fromCharCodes(responseData);
      final jsonResponse = json.decode(result);

      if (jsonResponse['secure_url'] != null) {
        return jsonResponse['secure_url'];
      } else {
        throw Exception('Upload failed: no secure_url in response');
      }
    } catch (e) {
      AppLogger.error('Cloudinary bytes upload failed', e);
      rethrow;
    }
  }
}
