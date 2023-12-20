# Copyright 2017 Tecnativa - Carlos Dauden <carlos.dauden@tecnativa.com>
# License AGPL-3.0 or later (https://www.gnu.org/licenses/agpl-3).

import logging

import schwifty

from odoo import api, models

from odoo.addons.base_iban.models.res_partner_bank import (
    _map_iban_template,
    normalize_iban,
    pretty_iban,
)

_logger = logging.getLogger(__name__)


class ResPartnerBank(models.Model):
    _inherit = "res.partner.bank"

    @api.model_create_multi
    def create(self, vals_list):
        vals_list = [self._add_bank_vals(vals) for vals in vals_list]
        return super().create(vals_list)

    def write(self, vals):
        self._add_bank_vals(vals)
        return super().write(vals)

    def _add_bank_vals(self, vals):
        if vals.get("acc_number") and not vals.get("bank_id"):
            try:
                bank = self._get_bank_from_iban(vals["acc_number"])
                vals["bank_id"] = bank.id
            except Exception:
                _logger.info("Could not find bank from IBAN", exc_info=True)
        return vals

    @api.model
    def _get_bank_from_iban(self, acc_number):
        iban = schwifty.IBAN(acc_number)
        country_code = iban.country_code.lower()
        country = self.env.ref("base.%s" % country_code, raise_if_not_found=False)
        vals = {
            "name": iban.bank["name"],
            "bic": iban.bank["bic"],
            "code": iban.bank["bank_code"],
            "country": country.id,
        }
        domain = [("code", "=", iban.bank["bank_code"])]
        bank = self.env["res.bank"].search(domain)
        if bank and len(bank) == 1:
            for field in vals:
                if not bank[field]:
                    bank[field] = vals[field]
        else:
            bank = self.env["res.bank"].create(vals)
        return bank

    @api.onchange("acc_number", "acc_type")
    def _onchange_acc_number_base_bank_from_iban(self):
        if self.acc_type != "iban":
            return
        acc_number = pretty_iban(normalize_iban(self.acc_number)).upper()
        country_code = self.acc_number[:2].lower()
        iban_template = _map_iban_template[country_code]
        first_match = iban_template[2:].find("B") + 2
        last_match = iban_template.rfind("B") + 1
        bank_code = acc_number[first_match:last_match].replace(" ", "")
        bank = self.env["res.bank"].search(
            [("code", "=", bank_code), ("country.code", "=", country_code.upper())],
            limit=1,
        )
        self.update({"bank_id": bank.id, "acc_number": acc_number})
