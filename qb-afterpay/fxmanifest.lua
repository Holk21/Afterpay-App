fx_version 'cerulean'
game 'gta5'

author 'Braiden Marshall'
description 'Afterpay-style BNPL for QBCore: anchored billing, fuel checkout, offline charging/late fees, merchant payouts.'
version '2.0.0'

lua54 'yes'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'qb-core'
}
