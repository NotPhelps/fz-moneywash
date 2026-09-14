Config = {}

-- Framework
Config.Framework = "qbox" -- "qbox", "qb", "esx", "auto"

-- Notifications
Config.Notify = "ox" -- "qb", "esx", "ox"

-- Money
-- Qbox uses "cash", "bank", or "crypto".
Config.MoneyType = "cash"

Config.debug = false
Config.useTarget = true
Config.keybind = 38

-- Items
Config.moneywashCard = 'moneywash_card'
Config.dirtycashItem = 'black_money'

-- Default fallback tax if a site doesn't have its own defined
Config.tax = 0.2

-- Maximum washing time in minutes
Config.maxwashtime = 1

Config.moneywashes = { 
    moneywash1 = { 
        requireCard = true,
        tax = 0.50, -- Unique tax for this specific site (20%)
        entrance = vec4(636.46, 2786.18, 42.21, 2.56), 
        exit = vec4(1138.09, -3199.13, -39.67, 185.48), 
        washingmachines = { 
            [1] = { coords = vec4(1126.97, -3194.25, -40.4, 3.58) }, 
            [2] = { coords = vec4(1125.5, -3194.27, -40.4, 1.34) }, 
            [3] = { coords = vec4(1123.76, -3194.28, -40.4, 3.94) }, 
        }, 
        zoneOptions = { length = 1.0, width = 1.0 }, 
    }, 
    
    moneywash2 = { 
        requireCard = true,
        tax = 0.0, -- Different unique tax for this second site (10%)
        entrance = vec4(35.59, 153.88, 117.52, 338), 
        exit = vec4(1173.69, -3196.46, -39.01, 267), 
        washingmachines = { 
            [1] = { coords = vec4(1169.51, -3196.96, -39.09, 90) },
        },
        zoneOptions = { length = 1.0, width = 1.0 }, 
    }
}
