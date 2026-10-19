<?php
// Run once with WP-CLI after installing and activating the custom theme.
if (!defined('ABSPATH') || !defined('WP_CLI')) { exit; }
$paragraph = fn($text) => '<!-- wp:paragraph --><p>' . $text . '</p><!-- /wp:paragraph -->';
$heading = fn($text) => '<!-- wp:heading --><h2 class="wp-block-heading">' . $text . '</h2><!-- /wp:heading -->';
$shortcode = fn($text) => '<!-- wp:shortcode -->' . $text . '<!-- /wp:shortcode -->';
$pages = [
    'home' => ['Home', file_get_contents(__DIR__ . '/content/home.html')],
    'about' => ['A shared road ahead.', $paragraph('We are the Leicestershire &amp; Rutland Widows Sons — a chapter brought together by motorcycling, friendship and the fellowship of Freemasonry.') . $heading('More than the destination.') . $paragraph('Riding brings us together. Our chapter website is a place to discover public rides and events, hear chapter news and follow the good causes we support.') . $paragraph('If you would like to learn about the chapter, ask about getting involved or discuss a community event, <a href="/contact/">get in touch with the chapter team</a>. They can explain membership and guest participation.')],
    'rides' => ['Out on the road.', $paragraph('Find our upcoming public rides and chapter events. Each published listing includes the details approved for sharing. Please contact the chapter before joining a ride, and check the event details before setting off.') . $shortcode('[ws_events]')],
    'charity' => ['A good ride can do more.', $paragraph('Charity and community are part of the chapter’s purpose. This is where we share approved fundraising stories, the causes we support and ways to get involved.') . $shortcode('[ws_charity]') . $heading('Bring a good cause to the chapter.') . $paragraph('Have a community project or fundraising idea? <a href="/contact/">Start a conversation with the chapter team</a>.')],
    'news' => ['Around the chapter.', $paragraph('Chapter updates, ride reports and stories from along the way.') . $shortcode('[ws_news]')],
    'gallery' => ['Miles and memories.', $paragraph('A place for approved photographs from our rides, gatherings and charity activities. Albums are published by the chapter team with permission from the people featured.') . $shortcode('[ws_gallery]')],
    'contact' => ['Start a conversation.', $paragraph('Ask about the chapter, a public event, membership or a charity idea. Your enquiry is saved privately for the chapter team to review. This form is for general chapter enquiries; please keep confidential welfare matters and emergencies out of it.') . $shortcode('[ws_contact]')],
];
foreach ($pages as $slug => [$title, $content]) {
    $existing = get_page_by_path($slug);
    if (!$existing) {
        $id = wp_insert_post(['post_type' => 'page', 'post_status' => 'publish', 'post_name' => $slug, 'post_title' => $title, 'post_content' => $content], true);
        if (is_wp_error($id)) { throw new RuntimeException($id->get_error_message()); }
    }
}
update_option('show_on_front', 'page');
update_option('page_on_front', get_page_by_path('home')->ID);
update_option('blogdescription', 'Motorcycling. Friendship. Charity.');
update_option('timezone_string', 'Europe/London');
update_option('date_format', 'j F Y');
update_option('time_format', 'H:i');
update_option('users_can_register', 0);
update_option('default_comment_status', 'closed');
update_option('default_ping_status', 'closed');
update_option('blog_public', 0); // Development site; enable discovery only at launch.
update_option('permalink_structure', '/%postname%/');
$welcome = get_page_by_path('welcome-to-the-chapter-website', OBJECT, 'post');
if (!$welcome) {
    wp_insert_post(['post_type' => 'post', 'post_status' => 'publish', 'post_name' => 'welcome-to-the-chapter-website', 'post_title' => 'A new home for chapter news.', 'post_excerpt' => 'Our chapter website brings public rides, charity stories and chapter updates together in one place.', 'post_content' => $paragraph('Welcome to the Leicestershire &amp; Rutland Widows Sons website. This is our place to share chapter news, public rides and approved charity updates.') . $paragraph('The chapter team will add dates and stories as they are confirmed. If you would like to find out more, use our <a href="/contact/">contact page</a>.')]);
}
foreach (get_posts(['post_type' => 'post', 'name' => 'hello-world', 'post_status' => 'any']) as $post) { wp_trash_post($post->ID); }
flush_rewrite_rules();
echo "Chapter pages and editor content ready.\n";
