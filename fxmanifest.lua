fx_version 'cerulean'
game 'gta5'

author 'Braiden Marshall'
description 'IRL-style Afterpay BNPL for QBCore with anchored billing days'
version '1.1.0'

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
