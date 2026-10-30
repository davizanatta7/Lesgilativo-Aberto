class CreatePropostas < ActiveRecord::Migration[8.1]
  def change
    create_table :propostas do |t|
      t.string :external_id, null: false
      t.string :casa, null: false
      t.string :sigla_tipo, null: false
      t.string :descricao_tipo
      t.string :numero
      t.integer :ano
      t.text :ementa
      t.text :ementa_detalhada
      t.text :keywords
      t.date :data_apresentacao
      t.string :status_situacao
      t.string :status_orgao
      t.text :status_despacho
      t.string :status_regime
      t.string :url_inteiro_teor
      t.string :uri_api
      t.datetime :detalhes_sincronizados_em

      t.timestamps
    end

    add_index :propostas, [ :casa, :external_id ], unique: true
    add_index :propostas, :casa
    add_index :propostas, :sigla_tipo
    add_index :propostas, :ano
    add_index :propostas, :data_apresentacao
  end
end

