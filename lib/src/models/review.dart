class Review {
  const Review({
    required this.id,
    required this.orderId,
    required this.reviewerId,
    required this.userId,
    required this.rating,
    this.comment,
    this.createdAt,
  });

  final String id;
  final String orderId;
  final String reviewerId;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id']?.toString() ?? '',
        orderId: json['order_id']?.toString() ?? '',
        reviewerId: json['reviewer_id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );
}
