class AppAssetModel {
  final String id;
  final String key;
  final String name;
  final String type;
  final String category;
  final String subcategory;
  final String localPath;
  final String? remoteUrl;
  final String? defaultValue;
  final String? mimeType;
  final int fileSize;
  final int? width;
  final int? height;
  final int sortOrder;
  final bool isActive;

  AppAssetModel({
    required this.id,
    required this.key,
    required this.name,
    required this.type,
    required this.category,
    this.subcategory = '',
    required this.localPath,
    this.remoteUrl,
    this.defaultValue,
    this.mimeType,
    this.fileSize = 0,
    this.width,
    this.height,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory AppAssetModel.fromJson(Map<String, dynamic> json) {
    return AppAssetModel(
      id: json['id'] as String? ?? json['key'] as String? ?? '',
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'image',
      category: json['category'] as String? ?? 'other',
      subcategory: json['subcategory'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      remoteUrl: (json['remote_url'] ?? json['url']) as String?,
      defaultValue: json['default_value'] as String?,
      mimeType: json['mime_type'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'name': name,
      'type': type,
      'category': category,
      'subcategory': subcategory,
      'local_path': localPath,
      'remote_url': remoteUrl,
      'default_value': defaultValue,
      'mime_type': mimeType,
      'file_size': fileSize,
      'width': width,
      'height': height,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }
}
