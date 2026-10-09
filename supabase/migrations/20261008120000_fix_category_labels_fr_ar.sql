-- Restore clean French and Arabic category labels by stable slug.
-- Scope: public.categories labels only. No product/order/chat data is changed.

with labels(slug, name_fr, name_ar) as (
  values
    ('women', 'Femmes', 'نساء'),
    ('men', 'Hommes', 'رجال'),
    ('kids', 'Enfants', 'أطفال'),
    ('home', 'Maison', 'المنزل'),
    ('beauty', 'Beauté & Santé', 'الجمال والصحة'),
    ('electronics', 'Électronique', 'إلكترونيات'),
    ('sports', 'Sport & Outdoor', 'رياضة وخارجية'),
    ('media', 'Livres & Divertissement', 'كتب وترفيه'),
    ('toys', 'Jouets & Jeux', 'ألعاب'),
    ('other', 'Autres', 'أخرى'),
    ('women-clothing', 'Vêtements', 'ملابس'),
    ('women-shoes', 'Chaussures', 'أحذية'),
    ('women-bags', 'Sacs', 'حقائب'),
    ('women-accessories', 'Accessoires', 'إكسسوارات'),
    ('women-jewelry', 'Bijoux', 'مجوهرات'),
    ('women-lingerie', 'Lingerie', 'ملابس داخلية'),
    ('men-clothing', 'Vêtements', 'ملابس'),
    ('men-shoes', 'Chaussures', 'أحذية'),
    ('men-accessories', 'Accessoires', 'إكسسوارات'),
    ('men-bags', 'Sacs', 'حقائب'),
    ('men-watches', 'Montres', 'ساعات'),
    ('kids-baby', 'Bébé (0-24 mois)', 'رضع (0-24 شهر)'),
    ('kids-clothing', 'Vêtements', 'ملابس'),
    ('kids-shoes', 'Chaussures', 'أحذية'),
    ('kids-accessories', 'Accessoires', 'إكسسوارات'),
    ('kids-school', 'École', 'لوازم مدرسية'),
    ('home-furniture', 'Meubles', 'أثاث'),
    ('home-decor', 'Décoration', 'ديكور'),
    ('home-kitchen', 'Cuisine', 'مطبخ'),
    ('home-textiles', 'Textiles', 'منسوجات'),
    ('home-appliances', 'Électroménager', 'أجهزة منزلية'),
    ('beauty-makeup', 'Maquillage', 'مكياج'),
    ('beauty-skincare', 'Soins de la peau', 'عناية بالبشرة'),
    ('beauty-hair', 'Cheveux', 'العناية بالشعر'),
    ('beauty-fragrance', 'Parfums', 'عطور'),
    ('beauty-wellness', 'Bien-être', 'العناية والرفاه'),
    ('electronics-phones', 'Téléphones', 'هواتف'),
    ('electronics-computers', 'Ordinateurs', 'حواسيب'),
    ('electronics-tablets', 'Tablettes', 'أجهزة لوحية'),
    ('electronics-audio', 'Audio', 'صوتيات'),
    ('electronics-gaming', 'Gaming', 'ألعاب'),
    ('electronics-accessories', 'Accessoires', 'إكسسوارات'),
    ('sports-clothing', 'Vêtements de sport', 'ملابس رياضية'),
    ('sports-shoes', 'Chaussures de sport', 'أحذية رياضية'),
    ('sports-equipment', 'Équipement', 'معدات'),
    ('sports-bikes', 'Vélos', 'دراجات'),
    ('sports-outdoor', 'Camping & Outdoor', 'تخييم وخارجية'),
    ('media-books', 'Livres', 'كتب'),
    ('media-movies', 'Films & Séries', 'أفلام ومسلسلات'),
    ('media-music', 'Musique', 'موسيقى'),
    ('media-games', 'Jeux vidéo', 'ألعاب فيديو'),
    ('toys-figures', 'Figurines', 'مجسمات'),
    ('toys-boardgames', 'Jeux de société', 'ألعاب جماعية'),
    ('toys-construction', 'Construction', 'تركيب وبناء'),
    ('toys-baby', 'Jouets bébé', 'ألعاب للرضع'),
    ('other-services', 'Services', 'خدمات'),
    ('other-collectibles', 'Collections', 'مقتنيات'),
    ('other-misc', 'Divers', 'متنوع')
)
update public.categories c
set name = labels.name_fr,
    name_fr = labels.name_fr,
    name_ar = labels.name_ar
from labels
where c.slug = labels.slug
  and (
    c.name is distinct from labels.name_fr
    or c.name_fr is distinct from labels.name_fr
    or c.name_ar is distinct from labels.name_ar
  );
