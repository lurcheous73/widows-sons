<?php
if (!defined('ABSPATH')) { exit; }
add_action('after_setup_theme', function () {
    add_theme_support('editor-styles');
    add_editor_style('style.css');
    add_theme_support('post-thumbnails');
});
add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style('widows-sons', get_stylesheet_uri(), [], '0.2.0');
});
