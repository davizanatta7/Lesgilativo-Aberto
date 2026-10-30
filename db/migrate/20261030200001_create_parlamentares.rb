class CreateParlamentares < ActiveRecord::Migration[8.1]
  def change
    create_table :parlamentares do |t|
      t.string :external_id, null: false
      t.string :casa, null: false
      t.string :nome, null: false
      t.string :nome_civil
      t.string :partido
      t.string :uf
      t.string :foto_url
      t.string :email
      t.string :telefone
      t.string :gabinete_predio
      t.string :gabinete_andar
      t.string :gabinete_sala
      t.string :situacao
      t.string :escolaridade
      t.date :data_nascimento
      t.string :municipio_nascimento
      t.string :uf_nascimento
      t.string :url_website
      t.json :redes_sociais, default: []
      t.datetime :dados_sincronizados_em
      t.datetime :propostas_sincronizadas_em

      t.timestamps
    end

    add_index :parlamentares, [ :casa, :external_id ], unique: true
    add_index :parlamentares, :casa
    add_index :parlamentares, :partido
    add_index :parlamentares, :uf
    add_index :parlamentares, :nome
  end
end

