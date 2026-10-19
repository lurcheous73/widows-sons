<?php
/** Plugin Name: Widows Sons Chapter Website
 * Description: Chapter content, editor tools and private enquiries for this website.
 * Version: 0.2.0
 */
if (!defined('ABSPATH')) { exit; }

add_action('init', function () {
    foreach (['ws_event' => ['Rides & events', 'Ride or event', 'dashicons-location-alt'], 'ws_charity' => ['Charity stories', 'Charity story', 'dashicons-heart'], 'ws_gallery' => ['Photo albums', 'Photo album', 'dashicons-format-gallery']] as $type => $label) {
        register_post_type($type, ['labels' => ['name' => $label[0], 'singular_name' => $label[1], 'add_new_item' => 'Add ' . strtolower($label[1])], 'public' => true, 'show_in_rest' => true, 'has_archive' => false, 'menu_icon' => $label[2], 'supports' => ['title', 'editor', 'excerpt', 'thumbnail', 'revisions', 'custom-fields'], 'rewrite' => ['slug' => str_replace('ws_', '', $type)]]);
    }
    register_post_type('ws_enquiry', ['labels' => ['name' => 'Chapter enquiries', 'singular_name' => 'Enquiry'], 'public' => false, 'show_ui' => true, 'show_in_rest' => false, 'exclude_from_search' => true, 'menu_icon' => 'dashicons-email', 'supports' => ['title', 'editor'], 'capabilities' => ['create_posts' => 'do_not_allow'], 'map_meta_cap' => true]);
    foreach (['_ws_starts_at', '_ws_location'] as $key) {
        register_post_meta('ws_event', $key, ['type' => 'string', 'single' => true, 'show_in_rest' => true, 'sanitize_callback' => 'sanitize_text_field', 'auth_callback' => function ($allowed, $meta_key, $post_id) { return current_user_can('edit_post', $post_id); }]);
    }
    if (!get_role('ws_chapter_editor')) {
        $caps = get_role('editor')->capabilities;
        $caps['edit_theme_options'] = true;
        add_role('ws_chapter_editor', 'Chapter editor', $caps);
    }
});

add_action('add_meta_boxes_ws_event', function () {
    add_meta_box('ws_event_details', 'When and where', function ($post) {
        wp_nonce_field('ws_save_event', 'ws_event_nonce');
        echo '<p><label for="ws_starts_at">Start date and time (chapter local time)</label></p><input id="ws_starts_at" name="ws_starts_at" type="datetime-local" value="' . esc_attr(get_post_meta($post->ID, '_ws_starts_at', true)) . '">';
        echo '<p><label for="ws_location">Public meeting place — leave private locations out</label></p><input class="widefat" id="ws_location" name="ws_location" value="' . esc_attr(get_post_meta($post->ID, '_ws_location', true)) . '">';
    });
});
add_action('save_post_ws_event', function ($id) {
    if (wp_is_post_revision($id) || !current_user_can('edit_post', $id) || empty($_POST['ws_event_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['ws_event_nonce'])), 'ws_save_event')) { return; }
    $date = sanitize_text_field(wp_unslash($_POST['ws_starts_at'] ?? ''));
    $valid = DateTimeImmutable::createFromFormat('!Y-m-d\TH:i', $date, wp_timezone());
    if ($date === '' || ($valid && $valid->format('Y-m-d\TH:i') === $date)) { update_post_meta($id, '_ws_starts_at', $date); }
    update_post_meta($id, '_ws_location', sanitize_text_field(wp_unslash($_POST['ws_location'] ?? '')));
});

function ws_public_events($limit = 50) {
    return get_posts(['post_type' => 'ws_event', 'post_status' => 'publish', 'posts_per_page' => min(100, max(1, (int) $limit)), 'meta_key' => '_ws_starts_at', 'orderby' => 'meta_value', 'order' => 'ASC', 'meta_query' => [['key' => '_ws_starts_at', 'value' => current_datetime()->format('Y-m-d\TH:i'), 'compare' => '>=']]]);
}
function ws_content_cards($posts, $kind) {
    if (!$posts) {
        $message = ['events' => 'The next chapter rides and public events will appear here as dates are confirmed.', 'news' => 'Chapter news will appear here as stories are published.', 'charity' => 'Our chapter team will share approved fundraising updates and charity stories here.', 'gallery' => 'Approved chapter photographs and ride albums will appear here.'][$kind];
        return '<div class="ws-empty"><p>' . esc_html($message) . '</p><a href="' . esc_url(home_url('/contact/')) . '">Speak to the chapter ↗</a></div>';
    }
    $html = '<div class="ws-cards">';
    foreach ($posts as $post) {
        $meta = get_the_date('j F Y', $post);
        if ($kind === 'events') {
            $start = new DateTimeImmutable(get_post_meta($post->ID, '_ws_starts_at', true), wp_timezone());
            $meta = wp_date('D j M · H:i', $start->getTimestamp(), wp_timezone());
        }
        $html .= '<article class="ws-card"><p class="ws-meta">' . esc_html($meta) . '</p><h3><a href="' . esc_url(get_permalink($post)) . '">' . esc_html(get_the_title($post)) . '</a></h3><p>' . esc_html(wp_trim_words(get_the_excerpt($post), 28)) . '</p>';
        if ($kind === 'events' && get_post_meta($post->ID, '_ws_location', true)) { $html .= '<p>' . esc_html(get_post_meta($post->ID, '_ws_location', true)) . '</p>'; }
        $html .= '<a href="' . esc_url(get_permalink($post)) . '">Read more ↗</a></article>';
    }
    return $html . '</div>';
}
add_shortcode('ws_events', function ($atts) { $atts = shortcode_atts(['limit' => 50], $atts); return ws_content_cards(ws_public_events($atts['limit']), 'events'); });
foreach (['ws_news' => ['post', 'news'], 'ws_charity' => ['ws_charity', 'charity'], 'ws_gallery' => ['ws_gallery', 'gallery']] as $shortcode => $config) {
    add_shortcode($shortcode, function ($atts) use ($config) { $atts = shortcode_atts(['limit' => 12], $atts); return ws_content_cards(get_posts(['post_type' => $config[0], 'post_status' => 'publish', 'posts_per_page' => min(50, max(1, (int) $atts['limit']))]), $config[1]); });
}
add_action('rest_api_init', function () {
    register_rest_route('widows-sons/v1', '/events', ['methods' => 'GET', 'permission_callback' => '__return_true', 'callback' => function () {
        return ['organisation' => 'lr', 'events' => array_map(function ($post) {
            $date = new DateTimeImmutable(get_post_meta($post->ID, '_ws_starts_at', true), wp_timezone());
            return ['id' => 'cms-' . $post->ID, 'title' => get_the_title($post), 'description' => wp_strip_all_tags($post->post_content), 'starts_at' => $date->format(DATE_ATOM), 'location' => get_post_meta($post->ID, '_ws_location', true), 'url' => get_permalink($post), 'status' => 'published'];
        }, ws_public_events())];
    }]);
});

add_action('admin_post_nopriv_ws_enquiry', 'ws_store_enquiry');
add_action('admin_post_ws_enquiry', 'ws_store_enquiry');
function ws_store_enquiry() {
    $nonce = sanitize_text_field(wp_unslash($_POST['ws_nonce'] ?? ''));
    if (!wp_verify_nonce($nonce, 'ws_enquiry') || !empty($_POST['company_website'])) { wp_die('Please return to the contact page and try again.', 'Enquiry not submitted', ['response' => 400]); }
    $rate_key = 'ws_enquiry_' . hash_hmac('sha256', $_SERVER['REMOTE_ADDR'] ?? 'unknown', wp_salt());
    $count = (int) get_transient($rate_key);
    if ($count >= 5) { wp_die('Please wait before sending another enquiry.', 'Please wait', ['response' => 429]); }
    $name = sanitize_text_field(wp_unslash($_POST['name'] ?? ''));
    $email = sanitize_email(wp_unslash($_POST['email'] ?? ''));
    $message = sanitize_textarea_field(wp_unslash($_POST['message'] ?? ''));
    if (!$name || strlen($name) > 150 || !is_email($email) || strlen($email) > 254 || strlen($message) < 10 || strlen($message) > 5000 || empty($_POST['consent'])) { wp_die('Please enter your name, email and a message of 10–5000 characters, and agree to the contact notice.', 'Check your enquiry', ['response' => 400]); }
    $id = wp_insert_post(['post_type' => 'ws_enquiry', 'post_status' => 'private', 'post_title' => 'Enquiry from ' . $name, 'post_content' => $message, 'meta_input' => ['_ws_email' => $email, '_ws_name' => $name]], true);
    if (is_wp_error($id)) { wp_die('Your enquiry could not be saved. Please try again.', 'Enquiry not submitted', ['response' => 500]); }
    set_transient($rate_key, $count + 1, HOUR_IN_SECONDS);
    wp_safe_redirect(add_query_arg('received', '1', home_url('/contact/'))); exit;
}
add_shortcode('ws_contact', function () {
    ob_start();
    if (isset($_GET['received'])) { echo '<p class="ws-notice" role="status">Your enquiry has been saved for the chapter team. Thank you for getting in touch.</p>'; }
    ?>
    <form class="ws-form" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" method="post">
        <input type="hidden" name="action" value="ws_enquiry"><?php wp_nonce_field('ws_enquiry', 'ws_nonce'); ?>
        <label>Your name<input name="name" autocomplete="name" maxlength="150" required></label>
        <label>Email address<input name="email" type="email" autocomplete="email" maxlength="254" required></label>
        <label>How can we help?<textarea name="message" minlength="10" maxlength="5000" required></textarea></label>
        <label class="ws-honey" aria-hidden="true">Leave this blank<input name="company_website" tabindex="-1" autocomplete="off"></label>
        <label style="display:flex;align-items:start"><input type="checkbox" name="consent" value="1" required style="width:auto;margin-top:5px">I agree that the chapter team can use these details to respond to my enquiry. Please avoid confidential welfare or emergency information here.</label>
        <button type="submit">Send enquiry ↗</button>
    </form>
    <?php return ob_get_clean();
});
add_action('add_meta_boxes_ws_enquiry', function () {
    add_meta_box('ws_enquiry_email', 'Reply details', function ($post) { echo '<p>' . esc_html(get_post_meta($post->ID, '_ws_name', true)) . '</p><p><a href="mailto:' . esc_attr(get_post_meta($post->ID, '_ws_email', true)) . '">' . esc_html(get_post_meta($post->ID, '_ws_email', true)) . '</a></p>'; });
});
add_action('admin_menu', function () {
    add_menu_page('Chapter editing guide', 'Chapter guide', 'edit_pages', 'ws-guide', function () {
        echo '<div class="wrap"><h1>Widows Sons L&R · Chapter editor</h1><p>This dashboard manages the chapter website at <strong>wsmba.the-grange.uk</strong>.</p><h2>Everyday updates</h2><ol><li><strong>Pages:</strong> open Home or any chapter page, edit the text visually, then Update.</li><li><strong>Posts:</strong> publish chapter news. It appears automatically on the home page and News.</li><li><strong>Rides &amp; events:</strong> add the title, description, start time and public meeting place. Drafts stay private.</li><li><strong>Charity stories / Photo albums:</strong> publish approved stories or photographs using the block editor.</li><li><strong>Chapter enquiries:</strong> read privately saved contact requests and reply using your chapter email.</li><li><strong>Appearance → Editor:</strong> edit shared header, footer and navigation.</li></ol><p>Preview before publishing. Use revisions to recover an earlier version. Only publish photographs and personal details with permission.</p><h2>Development environment</h2><p>Canada VM20000 · Dedicated Widows Sons project. Email delivery is not configured; enquiries are saved here for manual follow-up.</p></div>';
    }, 'dashicons-book-alt', 3);
});
add_action('wp_dashboard_setup', function () { remove_meta_box('dashboard_primary', 'dashboard', 'side'); wp_add_dashboard_widget('ws_dashboard', 'Widows Sons L&R — website updates', function () { echo '<p>Welcome to your chapter website. Start with the <a href="admin.php?page=ws-guide">chapter editing guide</a>, add a ride or publish a chapter story.</p><p><strong>Dedicated development environment: Canada VM20000.</strong></p>'; }); });
add_filter('admin_footer_text', function () { return 'Widows Sons L&R · Chapter website · Canada VM20000'; });
add_filter('login_headerurl', function () { return home_url('/'); });
add_action('login_enqueue_scripts', function () { echo '<style>body.login{background:#111820}#login h1 a{background:none;width:auto;height:auto;color:#f4f0e8;font:30px Georgia;text-indent:0}#login h1 a:after{content:"Widows Sons L&R"}.login #backtoblog a,.login #nav a{color:#c49a59}</style>'; });
// Development mail stays local; no unsolicited email is sent by this environment.
add_filter('pre_wp_mail', '__return_false');
add_filter('xmlrpc_enabled', '__return_false');
add_filter('rest_endpoints', function ($endpoints) { foreach (array_keys($endpoints) as $route) { if (str_starts_with($route, '/wp/v2/users') && $route !== '/wp/v2/users/me' && !is_user_logged_in()) { unset($endpoints[$route]); } } return $endpoints; });
