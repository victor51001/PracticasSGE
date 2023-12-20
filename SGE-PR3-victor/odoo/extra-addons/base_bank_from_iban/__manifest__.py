# Copyright 2017 Tecnativa - Carlos Dauden
# Copyright 2018-2022 Tecnativa - Pedro M. Baeza
# License AGPL-3.0 or later (https://www.gnu.org/licenses/agpl-3).

{
    "name": "Bank from IBAN",
    "version": "16.0.2.0.0",
    "author": "Tecnativa, Odoo Community Association (OCA)",
    "website": "https://github.com/OCA/community-data-files",
    "category": "Localization",
    "license": "AGPL-3",
    "depends": ["base_iban"],
    "development_status": "Mature",
    "data": ["views/res_bank_view.xml"],
    "external_dependencies": {"python": ["schwifty"]},
    "installable": True,
}
