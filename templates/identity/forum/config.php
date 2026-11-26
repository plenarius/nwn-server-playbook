<?php
// Flarum's settings file, read from the container's environment so no password is ever in the image.
return [
    'debug' => false,
    'database' => [
        'driver' => 'mysql',
        'host' => getenv('DB_HOST'),
        'port' => 3306,
        'database' => getenv('DB_NAME'),
        'username' => getenv('DB_USER'),
        'password' => getenv('DB_PASSWORD'),
        'charset' => 'utf8mb4',
        'collation' => 'utf8mb4_unicode_ci',
        'prefix' => '',
        'strict' => false,
        'engine' => 'InnoDB',
        'prefix_indexes' => true,
    ],
    'url' => getenv('FORUM_URL'),
    'paths' => ['api' => 'api', 'admin' => 'admin'],
    'headers' => ['poweredByHeader' => false, 'referrerPolicy' => 'same-origin'],
];
