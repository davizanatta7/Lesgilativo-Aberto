class CreateVotacoes < ActiveRecord::Migration[8.1]
  def change
    create_table :votacoes do |t|
      t.string :external_id, null: false
      t.string :casa, null: false
      t.references :proposta, null: true, foreign_key: true
      t.string :proposta_identificacao
      t.string :orgao
      t.datetime :data
      t.text :descricao
      t.text :resumo_efeito
      t.integer :aprovacao
      t.integer :votos_sim, default: 0, null: false
      t.integer :votos_nao, default: 0, null: false
      t.integer :votos_outros, default: 0, null: false

      t.timestamps
    end

    add_index :votacoes, [ :casa, :external_id ], unique: true
    add_index :votacoes, :data

    create_table :votos_parlamentares do |t|
      t.references :votacao, null: false, foreign_key: true
      t.references :parlamentar, null: false, foreign_key: true
      t.string :tipo_voto, null: false
      t.string :partido_na_votacao
      t.string :uf_na_votacao

      t.timestamps
    end

    add_index :votos_parlamentares, [ :votacao_id, :parlamentar_id ], unique: true
    add_index :votos_parlamentares, [ :parlamentar_id, :tipo_voto ]

    add_column :parlamentares, :votos_count, :integer, default: 0, null: false
    add_column :parlamentares, :votos_sincronizados_em, :datetime
  end
end

