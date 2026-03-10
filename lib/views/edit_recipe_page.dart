import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/recipe.dart';
import 'dart:async' show unawaited;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/cloudinary_service.dart';
import '../services/app_logger.dart';
import '../services/input_validator.dart';

class EditRecipePage extends StatefulWidget {
  final String recipeId;
  final Map<String, dynamic> recipeData;

  const EditRecipePage({
    super.key,
    required this.recipeId,
    required this.recipeData,
  });

  @override
  State<EditRecipePage> createState() => _EditRecipePageState();
}

class _EditRecipePageState extends State<EditRecipePage> {
  final ImagePicker _picker = ImagePicker();
  final CloudinaryService _cloudinary = CloudinaryService();

  XFile? coverImageXFile; // ✅ use XFile instead of File
  String? coverImageUrl;

  late TextEditingController foodNameController;
  late TextEditingController descriptionController;
  late TextEditingController durationController;
  String selectedCategory = "Food";

  List<TextEditingController> ingredientControllers = [];
  List<TextEditingController> stepControllers = [];
  List<File?> stepImageFiles = [];
  List<String?> stepImageUrls = [];
  List<String?> ingredientErrors = [];
  List<String?> stepErrors = [];

  bool _isUploading = false;
  String? _foodNameError;
  String? _descriptionError;
  String? _durationError;

  @override
  void initState() {
    super.initState();
    final data = widget.recipeData;
    foodNameController = TextEditingController(text: data['title'] ?? '');
    descriptionController = TextEditingController(
      text: data['description'] ?? '',
    );
    durationController = TextEditingController(
      text: (data['cookingDuration'] ?? 30).toString(),
    );
    selectedCategory = data['category'] ?? 'Food';
    coverImageUrl = data['coverImageUrl'] ?? '';

    // Ingredients
    final ingredients = List<String>.from(data['ingredients'] ?? []);
    ingredientControllers = ingredients.isNotEmpty
        ? ingredients.map((s) => TextEditingController(text: s)).toList()
        : [TextEditingController()];
    ingredientErrors = List<String?>.filled(
      ingredientControllers.length,
      null,
      growable: true,
    );

    // Steps
    final steps = (data['steps'] as List<dynamic>? ?? []);
    if (steps.isNotEmpty) {
      stepControllers = steps
          .map((s) => TextEditingController(text: s['description'] ?? ''))
          .toList();
      stepImageUrls = steps.map((s) => s['imageUrl'] as String? ?? '').toList();
      stepImageFiles = List<File?>.filled(steps.length, null, growable: true);
      stepErrors = List<String?>.filled(steps.length, null, growable: true);
    } else {
      stepControllers = [TextEditingController()];
      stepImageFiles = [null];
      stepImageUrls = [''];
      stepErrors = [null];
    }
  }

  Future<void> pickCoverImage() async {
    final XFile? x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (x != null) {
      final bytes = await x.readAsBytes();
      final imageError = InputValidator.validateImageUpload(
        fileName: x.name,
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
      setState(() {
        coverImageXFile = x; // ✅ update XFile instead of File
      });
    }
  }

  Future<void> pickStepImage(int index) async {
    final XFile? x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (x != null) {
      final bytes = await x.readAsBytes();
      final imageError = InputValidator.validateImageUpload(
        fileName: x.name,
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
      setState(() => stepImageFiles[index] = File(x.path));
    }
  }

  void addIngredient() {
    setState(() {
      ingredientControllers.add(TextEditingController());
      ingredientErrors.add(null);
    });
  }

  void removeIngredient(int index) {
    if (ingredientControllers.length <= 1) return;
    setState(() {
      ingredientControllers[index].dispose();
      ingredientControllers.removeAt(index);
      ingredientErrors.removeAt(index);
    });
  }

  void addStepField() {
    setState(() {
      stepControllers.add(TextEditingController());
      stepImageFiles.add(null);
      stepImageUrls.add('');
      stepErrors.add(null);
    });
  }

  void removeStepField(int index) {
    if (stepControllers.length <= 1) return;
    setState(() {
      stepControllers[index].dispose();
      stepControllers.removeAt(index);
      stepImageFiles.removeAt(index);
      stepImageUrls.removeAt(index);
      stepErrors.removeAt(index);
    });
  }

  String? _validateFoodName() {
    final required = InputValidator.validateRequiredText(
      foodNameController.text,
      'Food name',
    );
    if (required != null) return required;
    return InputValidator.validateTitle(foodNameController.text);
  }

  String? _validateDescriptionField() {
    final required = InputValidator.validateRequiredText(
      descriptionController.text,
      'Description',
      maxLength: InputValidator.maxDescriptionLength,
    );
    if (required != null) return required;
    return InputValidator.validateDescription(descriptionController.text);
  }

  String? _validateDurationField() {
    return InputValidator.validatePositiveInteger(
      durationController.text,
      'Cooking duration',
      min: 1,
      max: 300,
    );
  }

  String? _validateIngredientField(int index) {
    return InputValidator.validateRequiredText(
      ingredientControllers[index].text,
      'Ingredient',
      maxLength: InputValidator.maxIngredientLength,
    );
  }

  String? _validateStepField(int index) {
    return InputValidator.validateRequiredText(
      stepControllers[index].text,
      'Step ${index + 1}',
      maxLength: InputValidator.maxStepLength,
    );
  }

  void _setDurationValue(int value) {
    final clamped = value.clamp(1, 300);
    durationController.value = TextEditingValue(
      text: clamped.toString(),
      selection: TextSelection.collapsed(offset: clamped.toString().length),
    );
  }

  bool _validateAllFields() {
    final foodError = _validateFoodName();
    final descriptionError = _validateDescriptionField();
    final durationError = _validateDurationField();
    final nextIngredientErrors = List<String?>.generate(
      ingredientControllers.length,
      _validateIngredientField,
    );
    final nextStepErrors = List<String?>.generate(
      stepControllers.length,
      _validateStepField,
    );

    setState(() {
      _foodNameError = foodError;
      _descriptionError = descriptionError;
      _durationError = durationError;
      for (int i = 0; i < ingredientErrors.length; i++) {
        ingredientErrors[i] = nextIngredientErrors[i];
      }
      for (int i = 0; i < stepErrors.length; i++) {
        stepErrors[i] = nextStepErrors[i];
      }
    });

    if (durationError == null) {
      _setDurationValue(int.parse(durationController.text.trim()));
    }

    return foodError == null &&
        descriptionError == null &&
        durationError == null &&
        !nextIngredientErrors.any((e) => e != null) &&
        !nextStepErrors.any((e) => e != null);
  }

  Future<void> _saveRecipe() async {
    // Validate inputs before saving
    if (!_validateAllFields()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields.')),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      // Cover image
      String newCoverUrl = coverImageUrl ?? '';
      if (coverImageXFile != null) {
        newCoverUrl = await _cloudinary.uploadFile(
          File(coverImageXFile!.path), // ✅ still works for mobile
          folder: 'recipes/covers',
        );
      }

      // Step images
      List<RecipeStep> steps = [];
      for (int i = 0; i < stepControllers.length; i++) {
        String imageUrl = stepImageUrls.length > i
            ? stepImageUrls[i] ?? ''
            : '';
        if (stepImageFiles.length > i && stepImageFiles[i] != null) {
          imageUrl = await _cloudinary.uploadFile(
            stepImageFiles[i]!,
            folder: 'recipes/steps',
          );
        }
        steps.add(
          RecipeStep(
            description: stepControllers[i].text.trim(),
            imageUrl: imageUrl,
          ),
        );
      }

      // Ingredients
      final ingredients = ingredientControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('recipes')
          .doc(widget.recipeId)
          .update({
            'title': foodNameController.text.trim(),
            'description': descriptionController.text.trim(),
            'coverImageUrl': newCoverUrl,
            'ingredients': ingredients,
            'steps': steps.map((s) => s.toJson()).toList(),
            'cookingDuration': int.parse(durationController.text.trim()),
            'category': selectedCategory,
          });

      unawaited(
        AppLogger.logInfo(
          LogEvent.recipeAction,
          'Recipe updated: ${foodNameController.text.trim()}',
          metadata: {'action': 'update', 'recipeId': widget.recipeId},
        ),
      );

      setState(() => _isUploading = false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isUploading = false);
      unawaited(
        AppLogger.logError(
          LogEvent.recipeAction,
          'Recipe update failed: ${e.toString().split('\n').first}',
          metadata: {'action': 'update_failed', 'recipeId': widget.recipeId},
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update recipe. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.black),
              ),
            ),
            const Text("Edit Recipe", style: TextStyle(color: Colors.black)),
          ],
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Fixed Cover picker & preview
                GestureDetector(
                  onTap: pickCoverImage,
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: coverImageXFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: kIsWeb
                                ? Image.network(
                                    coverImageXFile!
                                        .path, // ✅ blob/data URI on web
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : Image.file(
                                    File(
                                      coverImageXFile!.path,
                                    ), // ✅ File on mobile
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  ),
                          )
                        : (coverImageUrl != null && coverImageUrl!.isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              coverImageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image, size: 40),
                                Text("Add Cover Photo"),
                                Text(
                                  "(up to 12 Mb)",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Food Name",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: foodNameController,
                  maxLength: InputValidator.maxTitleLength,
                  onChanged: (_) {
                    setState(() => _foodNameError = _validateFoodName());
                  },
                  decoration: InputDecoration(
                    hintText: "Enter food name",
                    counterText: '',
                    errorText: _foodNameError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Description",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  maxLength: InputValidator.maxDescriptionLength,
                  onChanged: (_) {
                    setState(
                      () => _descriptionError = _validateDescriptionField(),
                    );
                  },
                  decoration: InputDecoration(
                    hintText: "Tell a little about your food",
                    counterText: '',
                    errorText: _descriptionError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Cooking Duration (in minutes)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () {
                        final val = int.tryParse(durationController.text) ?? 1;
                        if (val > 1) {
                          setState(() {
                            _setDurationValue(val - 1);
                            _durationError = _validateDurationField();
                          });
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: durationController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) {
                          setState(() => _durationError = _validateDurationField());
                        },
                        decoration: InputDecoration(
                          counterText: '',
                          errorText: _durationError,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () {
                        final val = int.tryParse(durationController.text) ?? 1;
                        if (val < 300) {
                          setState(() {
                            _setDurationValue(val + 1);
                            _durationError = _validateDurationField();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Category
                const Text(
                  "Category",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  items: ["Food", "Drink", "Dessert", "Snack"]
                      .map(
                        (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCategory = value ?? "Food";
                    });
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Ingredients",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...List.generate(ingredientControllers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ingredientControllers[i],
                            maxLength: InputValidator.maxIngredientLength,
                            onChanged: (_) {
                              setState(() {
                                ingredientErrors[i] = _validateIngredientField(i);
                              });
                            },
                            decoration: InputDecoration(
                              hintText: "Enter ingredient",
                              counterText: '',
                              errorText: ingredientErrors[i],
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (ingredientControllers.length > 1)
                          IconButton(
                            onPressed: () => removeIngredient(i),
                            icon: const Icon(
                              Icons.remove_circle,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: addIngredient,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Ingredient"),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Steps",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...List.generate(stepControllers.length, (i) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: stepControllers[i],
                        maxLines: 3,
                        maxLength: InputValidator.maxStepLength,
                        onChanged: (_) {
                          setState(() {
                            stepErrors[i] = _validateStepField(i);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Describe step ${i + 1}",
                          counterText: '',
                          errorText: stepErrors[i],
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => pickStepImage(i),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Add Step Image"),
                          ),
                          const SizedBox(width: 8),
                          if (stepImageFiles.length > i &&
                              stepImageFiles[i] != null)
                            Stack(
                              children: [
                                SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: kIsWeb
                                      ? (stepImageUrls.length > i &&
                                                stepImageUrls[i] != null &&
                                                stepImageUrls[i]!.isNotEmpty
                                            ? Image.network(
                                                stepImageUrls[i]!,
                                                fit: BoxFit.cover,
                                              )
                                            : const Icon(Icons.image))
                                      : Image.file(
                                          stepImageFiles[i]!,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        stepImageFiles[i] = null;
                                        // If there was a previous url, keep it unless user wants to clear both
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (stepImageUrls.length > i &&
                              stepImageUrls[i] != null &&
                              stepImageUrls[i]!.isNotEmpty)
                            Stack(
                              children: [
                                SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Image.network(
                                    stepImageUrls[i]!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        stepImageUrls[i] = '';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const Spacer(),
                          if (stepControllers.length > 1)
                            IconButton(
                              onPressed: () => removeStepField(i),
                              icon: const Icon(
                                Icons.remove_circle,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
                OutlinedButton.icon(
                  onPressed: addStepField,
                  icon: const Icon(Icons.add),
                  label: const Text("Add More Steps"),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saveRecipe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text("Save Changes"),
                ),
              ],
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    foodNameController.dispose();
    descriptionController.dispose();
    durationController.dispose();
    for (final c in ingredientControllers) {
      c.dispose();
    }
    for (final c in stepControllers) {
      c.dispose();
    }
    super.dispose();
  }
}
