// Mirrors the object pushed into state.cart inside addToCart() (main-actions.js)
class CartItem {
  final String id; // product id
  final String? color;
  int qty;
  final double price; // price at time of adding (getDisplayPrice snapshot)
  final String name;
  final String image;

  CartItem({
    required this.id,
    required this.color,
    required this.qty,
    required this.price,
    required this.name,
    required this.image,
  });

  factory CartItem.fromMap(Map<String, dynamic> m) => CartItem(
        id: m['id'] as String,
        color: m['color'] as String?,
        qty: (m['qty'] as num?)?.toInt() ?? 1,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        name: m['name'] as String? ?? '',
        image: m['image'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'color': color,
        'qty': qty,
        'price': price,
        'name': name,
        'image': image,
      };

  double get lineTotal => price * qty;
}
