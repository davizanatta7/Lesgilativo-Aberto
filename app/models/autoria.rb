class Autoria < ApplicationRecord
  self.table_name = "autorias"

  belongs_to :parlamentar, counter_cache: :propostas_count, touch: true
  belongs_to :proposta

  validates :parlamentar_id, uniqueness: { scope: :proposta_id }
end
