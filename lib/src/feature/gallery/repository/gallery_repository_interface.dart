import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

abstract class IGalleryRepository {
  Future<bool> requestPermission();
  void addChangeCallback(void Function(MethodCall call) fn);
  void startChangeNotify();
  void stopChangeNotify();
  Future<void> deleteImages(List<String> ids);
  Future<AssetPathEntity> getRootFolder();
  Future<List<AssetEntity>> loadImages(
    AssetPathEntity folder,
    int page,
    int size,
  );
}
