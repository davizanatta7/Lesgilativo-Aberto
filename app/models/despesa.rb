class Despesa < ApplicationRecord
  self.table_name = "despesas"

  belongs_to :parlamentar

  validates :external_doc_id, presence: true, uniqueness: { scope: :parlamentar_id }
  validates :tipo_despesa, presence: true

  scope :recentes, -> { order(ano: :desc, mes: :desc, data_documento: :desc, id: :desc) }
  scope :por_ano, ->(ano) { where(ano: ano.to_i) if ano.present? }
  scope :por_tipo, ->(tipo) { where(tipo_despesa: tipo) if tipo.present? }
end

