import 'dart:io';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_editor/src/feature/editor/model/image_settings.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:stream_bloc/stream_bloc.dart';

part 'editor_bloc.freezed.dart';
part 'editor_event.dart';
part 'editor_state.dart';

class EditorBloc extends StreamBloc<EditorEvent, EditorState> {
  late final AssetEntity _image;
  late Bitmap _bitMap;
  final List<ImageSettings> _settings = [];

  EditorBloc(AssetEntity image)
      : _image = image,
        _bitMap = Bitmap.blank(0, 0),
        super(const _Loading()) {
    add(const _LoadImageSettings());
  }

  double get _brightness {
    if (_settings.isEmpty) return 0;
    final operations = _settings.last.operations;
    if (operations.isEmpty) return 0;
    final brightnessOperations = operations.whereType<BitmapBrightness>();
    if (brightnessOperations.isEmpty) return 0;

    return brightnessOperations.first.brightnessFactor * 100;
  }

  double get _contrast {
    if (_settings.isEmpty) return 100;
    final operations = _settings.last.operations;
    if (operations.isEmpty) return 100;
    final contrastOperations = operations.whereType<BitmapContrast>();
    if (contrastOperations.isEmpty) return 100;

    return contrastOperations.first.contrastFactor * 100;
  }

  @override
  // ignore: long-method
  Stream<EditorState> mapEventToStates(EditorEvent event) => event.when(
        loadImageSettings: () => _performMutation(
          () async {
            final file = await _image.file;
            if (file == null) {
              throw Exception('Can not load image');
            }
            _bitMap = await Bitmap.fromProvider(FileImage(file));

            // TODO: restore previous settings

            _settings.add(ImageSettings(image: _image, operations: []));

            return _LoadSuccess(_bitMap.buildHeaded(), _brightness, _contrast);
          },
        ),
        changeImageSettings: (operation) => _performMutation(() async {
          final prevSettings = _settings.last;
          final operations = List<BitmapOperation>.from(prevSettings.operations)
            ..removeWhere((element) {
              if (element.runtimeType == BitmapFlip ||
                  element.runtimeType == BitmapRotate) {
                return false;
              }

              return element.runtimeType == operation.runtimeType;
            })
            ..add(operation);

          var bitMap = _bitMap.cloneHeadless();
          bitMap = bitMap.applyBatch(operations);
          _settings.add(ImageSettings(image: _image, operations: operations));

          return _LoadSuccess(bitMap.buildHeaded(), _brightness, _contrast);
        }),
        restorePreviousSettings: () => _performMutation(() async {
          if (_settings.length > 1) _settings.removeAt(_settings.length - 1);

          var bitMap = _bitMap.cloneHeadless();
          final operations = _settings.last.operations;
          bitMap = bitMap.applyBatch(operations);

          return _LoadSuccess(bitMap.buildHeaded(), _brightness, _contrast);
        }),
        saveToGallery: () => _performMutation(() async {
          final directory = await getApplicationDocumentsDirectory();
          final path = '${directory.path}/${_image.title}';
          final file = File(path);
          var bitMap = _bitMap.cloneHeadless();
          bitMap = bitMap.applyBatch(_settings.last.operations);
          await file.writeAsBytes(bitMap.buildHeaded());
          final isSaved =
              await GallerySaver.saveImage(file.absolute.path) ?? false;
          debugPrint(
            isSaved ? 'Image saved to gallery' : 'Image not saved to gallery',
          );

          return state;
        }),
        changeBrightnessValue: (double brightnessValue) => _performMutation(
          () async => Future.value(
            state.whenOrNull(
              loadSuccess: (image, _, contrastValue) => _LoadSuccess(
                image,
                brightnessValue,
                contrastValue,
              ),
            ),
          ),
        ),
        changeContrastValue: (double contrastValue) => _performMutation(
          () async => Future.value(
            state.whenOrNull(
              loadSuccess: (image, brightnessValue, _) => _LoadSuccess(
                image,
                brightnessValue,
                contrastValue,
              ),
            ),
          ),
        ),
      );

  Stream<EditorState> _performMutation(
    Future<EditorState> Function() body,
  ) async* {
    try {
      final newState = await body();
      yield newState;
    } on Object catch (e) {
      yield _LoadFailure(e.toString());
    }
  }
}
